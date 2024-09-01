defmodule FLAME.RailwayBackend.App do
  use Application

  def start(_type, _args) do
    children = [
      FLAME.RailwayBackend.NeuronConnection.Client
    ]

    Supervisor.start_link(
      children,
      name: FLAME.RailwayBackend.Supervisor,
      strategy: :one_for_one
    )
  end
end
