defmodule RulesEngine.ValidationNestedBindingsTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Compiler

  @tenant "test"

  describe "nested guard binding validation" do
    test "simple nested guards with valid bindings pass" do
      src = """
      rule "valid-nested" do
        when
          a: A(x: v)
          b: B(y: w)
          guard (v > 1 and w < 5)
        then
          emit Out(x: v, y: w)
      end
      """

      assert {:ok, _ir} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: false})
    end

    test "deeply nested and/or with valid bindings pass" do
      src = """
      rule "valid-deep" do
        when
          a: A(x: v)
          b: B(y: w)
          c: C(z: z)
          guard ((v > 1 and w < 3) or (v == 0 and z > 10))
        then
          emit Out(result: 42)
      end
      """

      assert {:ok, _ir} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: false})
    end

    test "nested guards with unknown binding in and clause fails" do
      src = """
      rule "invalid-and" do
        when
          a: A(x: v)
          guard (v > 1 and unknown_var < 5)
        then
          emit Out(x: v)
      end
      """

      assert {:error, errors} = Compiler.parse_and_compile(@tenant, src)
      assert Enum.any?(errors, &(&1.code == :unknown_binding and &1.message =~ "unknown_var"))
    end

    test "nested guards with unknown binding in or clause fails" do
      src = """
      rule "invalid-or" do
        when
          a: A(x: v)
          guard (v > 1 or missing_binding < 5)
        then
          emit Out(x: v)
      end
      """

      assert {:error, errors} = Compiler.parse_and_compile(@tenant, src)
      assert Enum.any?(errors, &(&1.code == :unknown_binding and &1.message =~ "missing_binding"))
    end

    test "deeply nested with unknown binding fails" do
      src = """
      rule "invalid-deep" do
        when
          a: A(x: v)
          b: B(y: w)
          guard ((v > 1 and w < 3) or (v == 0 and unknown_deep > 10))
        then
          emit Out(x: v, y: w)
      end
      """

      assert {:error, errors} = Compiler.parse_and_compile(@tenant, src)
      assert Enum.any?(errors, &(&1.code == :unknown_binding and &1.message =~ "unknown_deep"))
    end

    test "mixed valid and invalid bindings in complex expression fails" do
      src = """
      rule "mixed-invalid" do
        when
          a: A(x: v)
          b: B(y: w)
          guard (v > 1 and (w < valid_var or w > invalid_var))
        then
          emit Out(x: v, y: w)
      end
      """

      assert {:error, errors} = Compiler.parse_and_compile(@tenant, src)
      # Should catch both unknown bindings
      unknown_errors = Enum.filter(errors, &(&1.code == :unknown_binding))
      assert length(unknown_errors) == 2
      assert Enum.any?(unknown_errors, &(&1.message =~ "valid_var"))
      assert Enum.any?(unknown_errors, &(&1.message =~ "invalid_var"))
    end

    test "binding references in between expressions are validated" do
      src = """
      rule "between-invalid" do
        when
          a: A(x: v, date: d)
          guard d between unknown_start and unknown_end
        then
          emit Out(x: v)
      end
      """

      assert {:error, errors} = Compiler.parse_and_compile(@tenant, src)
      unknown_errors = Enum.filter(errors, &(&1.code == :unknown_binding))
      assert length(unknown_errors) == 2
      assert Enum.any?(unknown_errors, &(&1.message =~ "unknown_start"))
      assert Enum.any?(unknown_errors, &(&1.message =~ "unknown_end"))
    end
  end
end
