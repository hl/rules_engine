defmodule RulesEngine.CalculatorsTest do
  use ExUnit.Case, async: true

  alias RulesEngine.Calculators

  doctest RulesEngine.Calculators

  describe "time_between/3" do
    test "calculates hours with decimal precision" do
      start = ~U[2023-01-01 09:00:00Z]
      finish = ~U[2023-01-01 10:30:00Z]

      result = Calculators.time_between(start, finish, :hours)
      assert result == Decimal.new("1.50")
    end

    test "calculates minutes as whole numbers" do
      start = ~U[2023-01-01 09:00:00Z]
      finish = ~U[2023-01-01 09:45:00Z]

      result = Calculators.time_between(start, finish, :minutes)
      assert result == Decimal.new("45")
    end

    test "handles negative durations" do
      start = ~U[2023-01-01 10:00:00Z]
      finish = ~U[2023-01-01 09:00:00Z]

      result = Calculators.time_between(start, finish, :hours)
      assert result == Decimal.new("-1.00")
    end

    test "handles zero duration" do
      dt = ~U[2023-01-01 10:00:00Z]

      result = Calculators.time_between(dt, dt, :hours)
      assert result == Decimal.new("0.00")
    end
  end

  describe "overlap_hours/4" do
    test "calculates overlap between overlapping periods" do
      a_start = ~U[2023-01-01 09:00:00Z]
      a_end = ~U[2023-01-01 12:00:00Z]
      b_start = ~U[2023-01-01 10:00:00Z]
      b_end = ~U[2023-01-01 14:00:00Z]

      result = Calculators.overlap_hours(a_start, a_end, b_start, b_end)
      assert result == Decimal.new("2.00")
    end

    test "returns zero for non-overlapping periods" do
      a_start = ~U[2023-01-01 09:00:00Z]
      a_end = ~U[2023-01-01 10:00:00Z]
      b_start = ~U[2023-01-01 11:00:00Z]
      b_end = ~U[2023-01-01 12:00:00Z]

      result = Calculators.overlap_hours(a_start, a_end, b_start, b_end)
      assert result == Decimal.new("0.00")
    end

    test "handles periods that touch at boundaries" do
      a_start = ~U[2023-01-01 09:00:00Z]
      a_end = ~U[2023-01-01 10:00:00Z]
      b_start = ~U[2023-01-01 10:00:00Z]
      b_end = ~U[2023-01-01 11:00:00Z]

      result = Calculators.overlap_hours(a_start, a_end, b_start, b_end)
      assert result == Decimal.new("0.00")
    end

    test "handles complete containment" do
      a_start = ~U[2023-01-01 09:00:00Z]
      a_end = ~U[2023-01-01 15:00:00Z]
      b_start = ~U[2023-01-01 10:00:00Z]
      b_end = ~U[2023-01-01 12:00:00Z]

      result = Calculators.overlap_hours(a_start, a_end, b_start, b_end)
      assert result == Decimal.new("2.00")
    end
  end

  describe "bucket/2-3" do
    test "creates day bucket with UTC timezone" do
      dt = ~U[2023-01-01 15:30:00Z]

      result = Calculators.bucket(:day, dt)
      assert result == {:day, "Etc/UTC", ~D[2023-01-01]}
    end

    test "creates week bucket for first week of year" do
      # Thursday of first week
      dt = ~U[2023-01-05 15:30:00Z]

      result = Calculators.bucket(:week, dt)
      assert result == {:week, "Etc/UTC", 2023, 1}
    end

    test "creates day bucket with custom timezone" do
      dt = ~U[2023-01-01 15:30:00Z]

      result = Calculators.bucket(:day, dt, "America/New_York")
      assert result == {:day, "America/New_York", ~D[2023-01-01]}
    end

    test "creates week bucket with custom timezone" do
      dt = ~U[2023-01-05 15:30:00Z]

      result = Calculators.bucket(:week, dt, "America/New_York")
      assert result == {:week, "America/New_York", 2023, 1}
    end
  end

  describe "decimal arithmetic" do
    test "decimal_add/2 adds two decimals" do
      a = Decimal.new("1.50")
      b = Decimal.new("2.25")

      result = Calculators.decimal_add(a, b)
      assert result == Decimal.new("3.75")
    end

    test "decimal_subtract/2 subtracts two decimals" do
      a = Decimal.new("5.00")
      b = Decimal.new("2.25")

      result = Calculators.decimal_subtract(a, b)
      assert result == Decimal.new("2.75")
    end

    test "decimal_multiply/2 multiplies two decimals" do
      a = Decimal.new("2.50")
      b = Decimal.new("3.00")

      result = Calculators.decimal_multiply(a, b)
      assert result == Decimal.new("7.50")
    end
  end

  describe "dec/1" do
    test "creates decimal from string" do
      result = Calculators.dec("12.50")
      assert result == Decimal.new("12.50")
    end

    test "creates decimal from zero string" do
      result = Calculators.dec("0")
      assert result == Decimal.new("0")
    end

    test "handles integer strings" do
      result = Calculators.dec("42")
      assert result == Decimal.new("42")
    end
  end
end
