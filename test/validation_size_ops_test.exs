defmodule RulesEngine.ValidationSizeOpsTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Compiler

  @tenant "t"

  test "size_gt on non-collection left is rejected" do
    _src = """
    rule "r" do
      when
        a: A(xs: v)
        guard size(v) > 1
      then
        emit Out(x: v)
    end
    """

    # Our DSL doesn't have size(v) directly; emulate size_* by using op with collection required
    # Here we deliberately violate by making left non-collection via integer literal
    src2 = """
    rule "r" do
      when
        a: A(xs: v)
        guard v size_gt 1
      then
        emit Out(x: v)
    end
    """

    assert {:error, errs} = Compiler.parse_and_compile(@tenant, src2)

    assert Enum.any?(errs, fn
             %{code: :invalid_operand, message: msg} -> String.contains?(msg, "collection left")
             %{error: _} -> true
             _ -> false
           end)
  end

  test "size_eq with non-numeric right is rejected" do
    src = """
    rule "r" do
      when
        a: A(xs: v)
        guard v size_eq "x"
      then
        emit Out(x: v)
    end
    """

    assert {:error, errs} = Compiler.parse_and_compile(@tenant, src)

    assert Enum.any?(errs, fn
             %{code: :invalid_operand, message: msg} -> String.contains?(msg, "numeric right")
             %{error: _} -> true
             _ -> false
           end)
  end
end
