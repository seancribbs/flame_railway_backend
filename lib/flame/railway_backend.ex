defmodule FLAME.RailwayBackend do
  @behaviour FLAME.Backend

  require Logger

  alias FLAME.RailwayBackend
  alias FLAME.RailwayBackend.NeuronConnection

  @derive {Inspect,
           only: [
             :project_id,
             :environment_id,
             :release_name,
             :service_name,
             :runner_node_name,
             :runner_service_id
           ]}

  defstruct project_id: nil,
            environment_id: nil,
            release_name: nil,
            service_name: nil,
            env: %{},
            source: %{},
            parent_ref: nil,
            runner_node_name: nil,
            runner_service_id: nil,
            remote_terminator_pid: nil,
            log: nil,
            terminator_sup: nil

  @valid_opts [
    :project_id,
    :environment_id,
    :release_name,
    :source,
    :env,
    :terminator_sup,
    :log
  ]

  @create_service_query """
    mutation serviceCreate($input: ServiceCreateInput!) {
      serviceCreate(input: $input) {
        createdAt
        deletedAt
        featureFlags
        icon
        id
        name
        projectId
        templateServiceId
        templateThreadSlug
        updatedAt
      }
    }
  """

  @deploy_service_query """
    mutation serviceDeploy($environmentId: String!, $serviceId: String!) {
      serviceInstanceDeploy(environmentId: $environmentId, serviceId: $serviceId)
    }
  """

  @delete_service_query """
  mutation serviceDelete($id: String!, $environmentId: String) {
    serviceDelete(id: $id, environmentId: $environmentId)
  }
  """

  @neuron_opts [connection_module: NeuronConnection]

  @impl true
  def init(opts) do
    conf = Application.get_env(:flame, __MODULE__) || []

    default = %RailwayBackend{
      project_id: System.get_env("RAILWAY_PROJECT_ID"),
      environment_id: System.get_env("RAILWAY_ENVIRONMENT_ID"),
      release_name: System.get_env("RELEASE_NAME"),
    }

    provided_opts =
      conf
      |> Keyword.merge(opts)
      |> Keyword.validate!(@valid_opts)

    %RailwayBackend{} = state = Map.merge(default, Map.new(provided_opts))

    state = %RailwayBackend{state | service_name: "#{state.release_name}-flame-#{rand_id(10)}"}

    for key <- [:project_id, :environment_id, :release_name, :env, :service_id] do
      unless Map.get(state, key) do
        raise ArgumentError, "missing :#{key} config for #{inspect(__MODULE__)}"
      end
    end

    unless state.source[:image] || state.source[:repo] do
      raise ArgumentError, "missing :source config for #{inspect(__MODULE__)} - either :image or :repo is required"
    end


    parent_ref = make_ref()

    encoded_parent =
      parent_ref
      |> FLAME.Parent.new(self(), __MODULE__, state.release_name, "RAILWAY_PRIVATE_DOMAIN")
      |> FLAME.Parent.encode()

    new_env =
      Map.merge(state.env, %{
        "PHX_SERVER" => "false",
        "FLAME_PARENT" => encoded_parent,
        "RELEASE_NODE" => "#{state.release_name}@${{ RAILWAY_PRIVATE_DOMAIN }}",
        "RELEASE_DISTRIBUTION" => "name",
        "RELEASE_COOKIE" => Atom.to_string(:erlang.get_cookie())
      })

    state = %RailwayBackend{state | env: new_env, parent_ref: parent_ref}
    {:ok, state}
  end

  @impl true
  def remote_boot(%RailwayBackend{parent_ref: parent_ref} = state) do
    input = %{
      name: state.service_name,
      environmentId: state.environment_id,
      projectId: state.project_id,
      source: state.source,
      variables: state.env
    }

    opts = [log: state.log] ++ @neuron_opts

    with {:ok, %{body: %{"data" => %{"serviceCreate" => service}}}} <-
           Neuron.query(@create_service_query, %{input: input}, opts),
         {:ok, %{body: %{"data" => %{"serviceInstanceDeploy" => true}}}} <-
           Neuron.query(
             @deploy_service_query,
             %{environmentId: state.environment_id, serviceId: service["id"]},
             opts
           ) do
      remote_terminator_pid =
        receive do
          {^parent_ref, {:remote_up, remote_terminator_pid}} ->
            remote_terminator_pid
        after
          30_000 ->
            Logger.error("failed to start service within 30s")
            exit(:timeout)
        end

      {:ok, remote_terminator_pid,
       %RailwayBackend{
         state
         | runner_service_id: service["id"],
           runner_node_name: node(remote_terminator_pid),
           remote_terminator_pid: remote_terminator_pid
       }}
    else
      err ->
        {:error, err}
    end
  end

  @impl true
  def remote_spawn_monitor(%RailwayBackend{} = state, term) do
    case term do
      func when is_function(func, 0) ->
        {pid, ref} = Node.spawn_monitor(state.runner_node_name, func)
        {:ok, {pid, ref}}

      {mod, fun, args} when is_atom(mod) and is_atom(fun) and is_list(args) ->
        {pid, ref} = Node.spawn_monitor(state.runner_node_name, mod, fun, args)
        {:ok, {pid, ref}}

      other ->
        raise ArgumentError,
              "expected a null arity function or {mod, func, args}. Got: #{inspect(other)}"
    end
  end

  @impl true
  def system_shutdown do
    System.stop()
  end

  @impl true
  def handle_info({ref, {:remote_shutdown, :idle}}, %RailwayBackend{parent_ref: ref} = state) do
    # Delete the service when the remote node has shut down
    variables = %{id: state.runner_service_id, environmentId: state.environment_id}

    new_state = %RailwayBackend{
      state
      | runner_node_name: nil,
        runner_service_id: nil,
        remote_terminator_pid: nil
    }

    case Neuron.query(@delete_service_query, variables, [log: state.log] ++ @neuron_opts) do
      {:ok, %{body: %{"data" => %{"serviceDelete" => true}}}} ->
        :ok

      err ->
        Logger.error("Error deleting service: #{inspect(err)}")
        :ok
    end

    {:noreply, new_state}
  end

  def handle_info(_other, state) do
    {:noreply, state}
  end

  defp rand_id(len) do
    len
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
    |> binary_part(0, len)
  end
end
