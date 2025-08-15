defmodule RulesEngine.HelpersTest do
  use ExUnit.Case, async: true

  alias RulesEngine.Helpers

  doctest RulesEngine.Helpers

  describe "to_datetime/1" do
    test "handles existing DateTime" do
      dt = ~U[2023-01-01 12:00:00Z]
      assert {:ok, ^dt} = Helpers.to_datetime(dt)
    end

    test "parses ISO8601 strings" do
      assert {:ok, ~U[2023-01-01 12:00:00Z]} = Helpers.to_datetime("2023-01-01T12:00:00Z")
      assert {:ok, dt} = Helpers.to_datetime("2023-01-01T12:00:00-05:00")
      assert %DateTime{} = dt
    end

    test "converts Unix timestamps" do
      # 2023-01-01 12:00:00 UTC
      assert {:ok, ~U[2023-01-01 12:00:00Z]} = Helpers.to_datetime(1_672_574_400)
    end

    test "returns error for invalid inputs" do
      assert {:error, {:iso8601_parse, _}} = Helpers.to_datetime("invalid")
      # -1 is valid in Unix (1969-12-31 23:59:59), use very large invalid timestamp
      assert {:error, {:unix_conversion, _}} = Helpers.to_datetime(999_999_999_999_999)
      assert {:error, :invalid_datetime_input} = Helpers.to_datetime(:atom)
    end
  end

  describe "to_decimal/1" do
    test "handles existing Decimal" do
      decimal = Decimal.new("12.50")
      assert {:ok, ^decimal} = Helpers.to_decimal(decimal)
    end

    test "converts integers" do
      assert {:ok, result} = Helpers.to_decimal(42)
      assert Decimal.equal?(result, Decimal.new("42"))
    end

    test "converts floats" do
      assert {:ok, result} = Helpers.to_decimal(3.14)
      assert Decimal.equal?(result, Decimal.new("3.14"))
    end

    test "parses valid strings" do
      assert {:ok, result} = Helpers.to_decimal("12.50")
      assert Decimal.equal?(result, Decimal.new("12.50"))
    end

    test "returns error for invalid strings" do
      assert {:error, {:decimal_parse, _}} = Helpers.to_decimal("invalid")
      assert {:error, {:decimal_parse, _}} = Helpers.to_decimal("12.50abc")
    end

    test "returns error for invalid inputs" do
      assert {:error, :invalid_decimal_input} = Helpers.to_decimal(:atom)
    end
  end

  describe "validate_collection/1" do
    test "validates lists" do
      assert {:ok, [1, 2, 3]} = Helpers.validate_collection([1, 2, 3])
      assert {:ok, []} = Helpers.validate_collection([])
    end

    test "rejects non-lists" do
      assert {:error, :not_a_collection} = Helpers.validate_collection("string")
      assert {:error, :not_a_collection} = Helpers.validate_collection(123)
      assert {:error, :not_a_collection} = Helpers.validate_collection(%{})
    end
  end

  describe "validate_numeric/1" do
    test "validates numbers" do
      assert {:ok, 42} = Helpers.validate_numeric(42)
      assert {:ok, 3.14} = Helpers.validate_numeric(3.14)
    end

    test "rejects non-numbers" do
      assert {:error, :not_numeric} = Helpers.validate_numeric("123")
      assert {:error, :not_numeric} = Helpers.validate_numeric(:atom)
    end
  end

  describe "validate_string/1" do
    test "validates strings" do
      assert {:ok, "hello"} = Helpers.validate_string("hello")
      assert {:ok, ""} = Helpers.validate_string("")
    end

    test "rejects non-strings" do
      assert {:error, :not_a_string} = Helpers.validate_string(123)
      assert {:error, :not_a_string} = Helpers.validate_string(:atom)
    end
  end

  describe "safe_divide/2" do
    test "performs division" do
      assert {:ok, 5.0} = Helpers.safe_divide(10, 2)
      assert {:ok, 2.5} = Helpers.safe_divide(5, 2)
    end

    test "handles division by zero" do
      assert {:error, :division_by_zero} = Helpers.safe_divide(10, 0)
      assert {:error, :division_by_zero} = Helpers.safe_divide(10, 0.0)
    end
  end

  describe "safe_decimal_divide/2" do
    test "performs decimal division" do
      dividend = Decimal.new("10")
      divisor = Decimal.new("2")
      assert {:ok, result} = Helpers.safe_decimal_divide(dividend, divisor)
      assert Decimal.equal?(result, Decimal.new("5"))
    end

    test "handles division by zero" do
      dividend = Decimal.new("10")
      divisor = Decimal.new("0")
      assert {:error, :division_by_zero} = Helpers.safe_decimal_divide(dividend, divisor)
    end
  end

  describe "clamp/3" do
    test "clamps values within range" do
      assert Helpers.clamp(5, 1, 10) == 5
    end

    test "clamps values below range" do
      assert Helpers.clamp(-5, 1, 10) == 1
    end

    test "clamps values above range" do
      assert Helpers.clamp(15, 1, 10) == 10
    end
  end

  describe "decimal_clamp/3" do
    test "clamps decimal values within range" do
      value = Decimal.new("5")
      min_val = Decimal.new("1")
      max_val = Decimal.new("10")

      result = Helpers.decimal_clamp(value, min_val, max_val)
      assert Decimal.equal?(result, value)
    end

    test "clamps decimal values below range" do
      value = Decimal.new("-5")
      min_val = Decimal.new("1")
      max_val = Decimal.new("10")

      result = Helpers.decimal_clamp(value, min_val, max_val)
      assert Decimal.equal?(result, min_val)
    end

    test "clamps decimal values above range" do
      value = Decimal.new("15")
      min_val = Decimal.new("1")
      max_val = Decimal.new("10")

      result = Helpers.decimal_clamp(value, min_val, max_val)
      assert Decimal.equal?(result, max_val)
    end
  end

  describe "round_to/2" do
    test "rounds to specified decimal places" do
      assert Helpers.round_to(3.14159, 2) == 3.14
      assert Helpers.round_to(3.14159, 0) == 3.0
      assert Helpers.round_to(3.14159, 4) == 3.1416
    end
  end

  describe "normalize_string/1" do
    test "trims and lowercases strings" do
      assert Helpers.normalize_string("  Hello World  ") == "hello world"
      assert Helpers.normalize_string("Test") == "test"
      assert Helpers.normalize_string("UPPERCASE") == "uppercase"
    end
  end

  describe "empty?/1" do
    test "detects empty values" do
      assert Helpers.empty?(nil)
      assert Helpers.empty?("")
      assert Helpers.empty?([])
      assert Helpers.empty?(%{})
    end

    test "detects non-empty values" do
      refute Helpers.empty?("hello")
      refute Helpers.empty?([1])
      refute Helpers.empty?(%{key: "value"})
      refute Helpers.empty?(42)
      # Zero is not empty
      refute Helpers.empty?(0)
    end
  end
end
