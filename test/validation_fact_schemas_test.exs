defmodule RulesEngine.ValidationFactSchemasTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Compiler

  @tenant "t"
  @schemas %{
    "A" => %{"fields" => ["x", "y"]},
    "Out" => %{"fields" => ["x"]}
  }

  test "unknown field in pattern is rejected when schemas provided" do
    src = """
    rule "r" do
      when
        a: A(x: v, z: 1)
      then
        emit Out(x: v)
    end
    """

    assert {:error, errs} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: @schemas})
    assert Enum.any?(errs, fn e -> e.code == :unknown_field end)
  end

  test "unknown emit field is allowed for now (no action schema enforcement)" do
    src = """
    rule "r" do
      when
        a: A(x: v)
      then
        emit Out(x: v)
    end
    """

    assert {:ok, _} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: @schemas})
  end
end
