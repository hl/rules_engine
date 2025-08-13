defmodule RulesEngineTest do
  use ExUnit.Case
  doctest RulesEngine

  test "greets the world" do
    assert RulesEngine.hello() == :world
  end
end
