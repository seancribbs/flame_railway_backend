defmodule FLAME.RailwayBackend.MixProject do
  use Mix.Project

  def project do
    [
      app: :flame_railway_backend,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {FLAME.RailwayBackend.App, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:flame, "~> 0.4.2"},
      {:neuron, "~> 5.1.0"},
      {:hardhat, "~> 1.1.0"}
    ]
  end
end
