defmodule RulesEngine.PredicatesTest do
  use ExUnit.Case, async: true

  alias RulesEngine.Predicates

  doctest RulesEngine.Predicates

  describe "supported_ops/0" do
    test "returns list of supported operations" do
      ops = Predicates.supported_ops()
      assert is_list(ops)
      assert :== in ops
      assert :starts_with in ops
      assert :before in ops
      assert :size_eq in ops
    end
  end

  describe "indexable?/1" do
    test "equality operations are indexable" do
      assert Predicates.indexable?(:==)
      assert Predicates.indexable?(:in)
      assert Predicates.indexable?(:between)
    end

    test "non-equality operations are not indexable" do
      refute Predicates.indexable?(:starts_with)
      refute Predicates.indexable?(:contains)
      refute Predicates.indexable?(:before)
      refute Predicates.indexable?(:matches)
    end
  end

  describe "selectivity_hint/1" do
    test "returns appropriate selectivity for operations" do
      # Most selective
      assert Predicates.selectivity_hint(:==) == 0.01
      assert Predicates.selectivity_hint(:in) == 0.1
      assert Predicates.selectivity_hint(:starts_with) == 0.15
      # Least selective string op
      assert Predicates.selectivity_hint(:contains) == 0.3
      # Default
      assert Predicates.selectivity_hint(:unknown_op) == 0.5
    end
  end

  describe "expectations/1" do
    test "returns correct type expectations" do
      assert %{datetime_required?: true} = Predicates.expectations(:before)
      assert %{datetime_required?: true} = Predicates.expectations(:after)

      assert %{collection_left?: true, numeric_right?: true} = Predicates.expectations(:size_eq)
      assert %{collection_left?: true, numeric_right?: true} = Predicates.expectations(:size_gt)

      assert %{string_left?: true, string_right?: true} = Predicates.expectations(:starts_with)
      assert %{string_left?: true, string_right?: true} = Predicates.expectations(:contains)

      assert %{string_left?: true, regex_right?: true} = Predicates.expectations(:matches)

      assert %{} = Predicates.expectations(:unknown_op)
    end
  end

  describe "evaluate/3 - basic comparisons" do
    test "equality operations" do
      assert Predicates.evaluate(:==, "hello", "hello")
      refute Predicates.evaluate(:==, "hello", "world")

      refute Predicates.evaluate(:!=, "hello", "hello")
      assert Predicates.evaluate(:!=, "hello", "world")
    end

    test "numeric comparisons" do
      assert Predicates.evaluate(:>, 5, 3)
      refute Predicates.evaluate(:>, 3, 5)

      assert Predicates.evaluate(:>=, 5, 5)
      assert Predicates.evaluate(:>=, 5, 3)

      assert Predicates.evaluate(:<, 3, 5)
      refute Predicates.evaluate(:<, 5, 3)

      assert Predicates.evaluate(:<=, 3, 3)
      assert Predicates.evaluate(:<=, 3, 5)
    end
  end

  describe "evaluate/3 - set operations" do
    test "membership operations" do
      assert Predicates.evaluate(:in, "apple", ["apple", "banana", "orange"])
      refute Predicates.evaluate(:in, "grape", ["apple", "banana", "orange"])

      refute Predicates.evaluate(:not_in, "apple", ["apple", "banana", "orange"])
      assert Predicates.evaluate(:not_in, "grape", ["apple", "banana", "orange"])
    end

    test "between operation" do
      assert Predicates.evaluate(:between, 5, {1, 10})
      # inclusive
      assert Predicates.evaluate(:between, 1, {1, 10})
      # inclusive
      assert Predicates.evaluate(:between, 10, {1, 10})
      refute Predicates.evaluate(:between, 15, {1, 10})
      refute Predicates.evaluate(:between, 0, {1, 10})
    end
  end

  describe "evaluate/3 - temporal operations" do
    test "overlap operation" do
      # Overlapping periods
      assert Predicates.evaluate(:overlap, {1, 5}, {3, 7})
      assert Predicates.evaluate(:overlap, {3, 7}, {1, 5})

      # Non-overlapping periods
      refute Predicates.evaluate(:overlap, {1, 3}, {5, 7})
      refute Predicates.evaluate(:overlap, {5, 7}, {1, 3})

      # Touching periods (no overlap)
      refute Predicates.evaluate(:overlap, {1, 3}, {3, 5})
    end

    test "before and after operations" do
      dt1 = ~U[2023-01-01 10:00:00Z]
      dt2 = ~U[2023-01-01 11:00:00Z]

      assert Predicates.evaluate(:before, dt1, dt2)
      refute Predicates.evaluate(:before, dt2, dt1)

      assert Predicates.evaluate(:after, dt2, dt1)
      refute Predicates.evaluate(:after, dt1, dt2)
    end
  end

  describe "evaluate/3 - string operations" do
    test "starts_with operation" do
      assert Predicates.evaluate(:starts_with, "hello world", "hello")
      assert Predicates.evaluate(:starts_with, "hello", "hello")
      refute Predicates.evaluate(:starts_with, "hello world", "world")
      refute Predicates.evaluate(:starts_with, "hi", "hello")
    end

    test "ends_with operation" do
      assert Predicates.evaluate(:ends_with, "hello world", "world")
      assert Predicates.evaluate(:ends_with, "world", "world")
      refute Predicates.evaluate(:ends_with, "hello world", "hello")
      refute Predicates.evaluate(:ends_with, "hi", "world")
    end

    test "contains operation" do
      assert Predicates.evaluate(:contains, "hello world", "lo wo")
      assert Predicates.evaluate(:contains, "hello world", "hello")
      assert Predicates.evaluate(:contains, "hello world", "world")
      refute Predicates.evaluate(:contains, "hello world", "xyz")
    end

    test "matches operation with regex" do
      pattern = ~r/^hello/i

      assert Predicates.evaluate(:matches, "Hello World", pattern)
      assert Predicates.evaluate(:matches, "hello world", pattern)
      refute Predicates.evaluate(:matches, "world hello", pattern)
    end
  end

  describe "evaluate/3 - collection operations" do
    test "size_eq operation" do
      assert Predicates.evaluate(:size_eq, [1, 2, 3], 3)
      assert Predicates.evaluate(:size_eq, [], 0)
      refute Predicates.evaluate(:size_eq, [1, 2], 3)
    end

    test "size_gt operation" do
      assert Predicates.evaluate(:size_gt, [1, 2, 3], 2)
      assert Predicates.evaluate(:size_gt, [1, 2, 3], 0)
      refute Predicates.evaluate(:size_gt, [1, 2], 3)
      refute Predicates.evaluate(:size_gt, [1, 2], 2)
    end
  end

  describe "evaluate/3 - numeric approximation" do
    test "approximately operation with numbers" do
      assert Predicates.evaluate(:approximately, 1.0, 1.00005)
      assert Predicates.evaluate(:approximately, 10, 10.00001)
      refute Predicates.evaluate(:approximately, 1.0, 1.1)
    end

    test "approximately operation with decimals" do
      assert Predicates.evaluate(:approximately, Decimal.new("1.00"), Decimal.new("1.005"))
      assert Predicates.evaluate(:approximately, Decimal.new("100.00"), Decimal.new("100.005"))
      refute Predicates.evaluate(:approximately, Decimal.new("1.00"), Decimal.new("1.10"))
    end
  end

  describe "evaluate/3 - network-level operations" do
    test "exists and not_exists raise errors" do
      assert_raise RuntimeError, ~r/exists\/not_exists handled by network evaluation/, fn ->
        Predicates.evaluate(:exists, :foo, :bar)
      end

      assert_raise RuntimeError, ~r/exists\/not_exists handled by network evaluation/, fn ->
        Predicates.evaluate(:not_exists, :foo, :bar)
      end
    end
  end
end
