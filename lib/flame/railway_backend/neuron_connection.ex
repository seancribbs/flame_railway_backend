defmodule FLAME.RailwayBackend.NeuronConnection do
  @moduledoc false
  require Logger

  defmodule Json do
    @moduledoc false

    defdelegate decode!(data), to: FLAME.Parser.JSON
    defdelegate encode!(term), to: FLAME.Parser.JSON

    def decode(data, _opts) do
      try do
        decode!(data)
      catch
        kind, value -> {:error, {kind, value}}
      else
        result -> {:ok, result}
      end
    end

    def encode(term, _opts) do
      try do
        encode!(term)
      catch
        kind, value -> {:error, {kind, value}}
      else
        result -> {:ok, result}
      end
    end
  end

  defmodule Client do
    @moduledoc false
    use Hardhat, strategy: :fuse

    plug Tesla.Middleware.BaseUrl,
         System.get_env("RAILWAY_API_URL", "https://backboard.railway.app/graphql/v2")

    plug Tesla.Middleware.BearerAuth, token: System.fetch_env!("RAILWAY_TOKEN")
    plug Tesla.Middleware.Headers, [{"content-type", "application/json"}]
    plug Tesla.Middleware.DecodeJson, engine: FLAME.RailwayBackend.NeuronConnection.Json
    plug Tesla.Middleware.Logger, debug: true

    def opentelemetry_opts do
      [
        # Disable trace propagation for talking to a third-party API
        propagator: :none
      ]
    end
  end

  @behaviour Neuron.Connection

  @impl Neuron.Connection
  def call(body, options) do
    request_opts = Keyword.take(options, ~w{headers query opts}a)

    if Keyword.get(options, :log) do
      Logger.log(options[:log], "GRAPHQL REQUEST: #{inspect(body)}")
    end

    case Client.post("", body, request_opts) do
      {:ok, %Tesla.Env{status: 200} = env} ->
        {:ok, build_response(env)}

      {:ok, env} ->
        {:error, build_response(env)}

      err ->
        err
    end
  end

  defp build_response(%Tesla.Env{status: status, headers: headers, body: body}) do
    %Neuron.Response{body: body, headers: headers, status_code: status}
  end
end
