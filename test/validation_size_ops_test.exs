defmodule RulesEngine.ValidationSizeOpsTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Compiler

  @tenant "t"

  defp read_fixture(filename) do
    File.read!(Path.join([__DIR__, "fixtures", "dsl", filename]))
  end

  test "size_gt on non-collection left is rejected" do
    src = read_fixture("validation_size_gt_non_collection.rule")
    assert {:error, errs} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: false})
    # With our mock expectations, we check for invalid_operand rather than unknown_binding
    assert Enum.any?(errs, &(&1.code == :invalid_operand))
  end

  test "size_eq with non-numeric right is rejected" do
    src = read_fixture("validation_size_eq_non_numeric.rule")
    assert {:error, errs} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: false})
    assert Enum.any?(errs, &(&1.code == :invalid_operand))
  end
end
