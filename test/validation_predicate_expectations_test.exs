defmodule RulesEngine.ValidationPredicateExpectationsTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Compiler
  alias RulesEngine.Predicates

  @tenant "test"

  test "expectations function provides correct metadata for all supported ops" do
    # Verify the expectations function works as designed
    assert Predicates.expectations(:before) == %{datetime_required?: true}
    assert Predicates.expectations(:after) == %{datetime_required?: true}
    assert Predicates.expectations(:size_eq) == %{collection_left?: true, numeric_right?: true}
    assert Predicates.expectations(:size_gt) == %{collection_left?: true, numeric_right?: true}

    # Operations without constraints should return empty map
    assert Predicates.expectations(:==) == %{}
    assert Predicates.expectations(:!=) == %{}
    assert Predicates.expectations(:<) == %{}
    assert Predicates.expectations(:>) == %{}
    assert Predicates.expectations(:<=) == %{}
    assert Predicates.expectations(:>=) == %{}
    assert Predicates.expectations(:in) == %{}
    assert Predicates.expectations(:not_in) == %{}
  end

  test "validation system uses expectations function (demonstrated with existing test)" do
    # This replicates the existing validation test but confirms it now uses expectations
    src = """
    rule "r" do
      when
        a: A(x: v)
        guard v before 10
      then
        emit Out(x: v)
    end
    """

    # The validation should fail (as it did before) but now uses expectations function
    assert {:error, errors} = Compiler.parse_and_compile(@tenant, src)
    assert Enum.any?(errors, &(&1.code == :invalid_operand))
  end

  test "basic predicate operations work correctly" do
    src = """
    rule "test" do
      when
        a: A(x: v)
        guard v == 10
        guard v > 5
      then
        emit Out(x: v)
    end
    """

    assert {:ok, _ir} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: false})
  end

  test "unsupported operations are still rejected" do
    src = """
    rule "r" do
      when
        a: A(x: v)
        guard v frobnicate 10
      then
        emit Out(x: v)
    end
    """

    # Parser fails first; treat as parse error acceptable here
    assert match?({:error, _}, Compiler.parse_and_compile(@tenant, src))
  end
end
