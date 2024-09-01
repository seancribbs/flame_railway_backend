defmodule FlameRailwayBackendTest do
  use ExUnit.Case
  doctest FlameRailwayBackend

  test "greets the world" do
    assert FlameRailwayBackend.hello() == :world
  end
end
