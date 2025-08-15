defmodule RulesEngine.Calculators do
  @moduledoc """
  Pure calculator functions for DSL expressions.

  Provides deterministic, side-effect free functions for time, decimal arithmetic,
  and bucketing operations used in rules processing.
  """

  @doc """
  Calculate time between two DateTime values in specified units.

  Returns a Decimal with appropriate precision:
  - Hours: scale 2 (e.g., "1.50" for 1 hour 30 minutes)  
  - Minutes: scale 0 (whole minutes only)

  Allows negative durations (finish before start).

  ## Examples

      iex> start = ~U[2023-01-01 09:00:00Z]
      iex> finish = ~U[2023-01-01 10:30:00Z]
      iex> RulesEngine.Calculators.time_between(start, finish, :hours)
      Decimal.new("1.50")

      iex> start = ~U[2023-01-01 09:00:00Z]
      iex> finish = ~U[2023-01-01 09:45:00Z]
      iex> RulesEngine.Calculators.time_between(start, finish, :minutes)
      Decimal.new("45")
  """
  @spec time_between(DateTime.t(), DateTime.t(), :hours | :minutes) :: Decimal.t()
  def time_between(%DateTime{} = start, %DateTime{} = finish, unit) do
    diff_seconds = DateTime.diff(finish, start, :second)

    case unit do
      :hours ->
        diff_seconds
        |> Decimal.div(3600)
        |> Decimal.round(2)

      :minutes ->
        diff_seconds
        |> Decimal.div(60)
        |> Decimal.round(0)
    end
  end

  @doc """
  Calculate overlapping hours between two time periods.

  Returns Decimal with scale 2 representing hours of overlap.
  Non-overlapping periods return "0.00".

  ## Examples

      iex> a_start = ~U[2023-01-01 09:00:00Z]
      iex> a_end = ~U[2023-01-01 12:00:00Z]
      iex> b_start = ~U[2023-01-01 10:00:00Z] 
      iex> b_end = ~U[2023-01-01 14:00:00Z]
      iex> RulesEngine.Calculators.overlap_hours(a_start, a_end, b_start, b_end)
      Decimal.new("2.00")
  """
  @spec overlap_hours(DateTime.t(), DateTime.t(), DateTime.t(), DateTime.t()) :: Decimal.t()
  def overlap_hours(
        %DateTime{} = a_start,
        %DateTime{} = a_end,
        %DateTime{} = b_start,
        %DateTime{} = b_end
      ) do
    overlap_start = datetime_max(a_start, b_start)
    overlap_end = datetime_min(a_end, b_end)

    if DateTime.compare(overlap_start, overlap_end) == :lt do
      time_between(overlap_start, overlap_end, :hours)
    else
      Decimal.new("0.00")
    end
  end

  @doc """
  Group DateTime into period buckets.

  Returns structured term for period identification:
  - Day bucket: `{:day, timezone, date}`
  - Week bucket: `{:week, timezone, year, iso_week}`

  Timezone defaults to the DateTime's timezone if not provided.

  ## Examples

      iex> dt = ~U[2023-01-01 15:30:00Z]
      iex> RulesEngine.Calculators.bucket(:day, dt)
      {:day, "Etc/UTC", ~D[2023-01-01]}

      iex> dt = ~U[2023-01-05 15:30:00Z] # Thursday
      iex> RulesEngine.Calculators.bucket(:week, dt)
      {:week, "Etc/UTC", 2023, 1}
  """
  @spec bucket(:day | :week, DateTime.t(), String.t() | nil) ::
          {:day, String.t(), Date.t()} | {:week, String.t(), integer(), integer()}
  def bucket(period, dt, tz \\ nil)

  def bucket(:day, %DateTime{} = dt, tz) do
    timezone = tz || dt.time_zone
    {:day, timezone, DateTime.to_date(dt)}
  end

  def bucket(:week, %DateTime{} = dt, tz) do
    timezone = tz || dt.time_zone
    date = DateTime.to_date(dt)
    {year, week} = :calendar.iso_week_number(Date.to_erl(date))
    {:week, timezone, year, week}
  end

  @doc """
  Add two Decimal values.

  ## Examples

      iex> RulesEngine.Calculators.decimal_add(Decimal.new("1.50"), Decimal.new("2.25"))
      Decimal.new("3.75")
  """
  @spec decimal_add(Decimal.t(), Decimal.t()) :: Decimal.t()
  def decimal_add(%Decimal{} = a, %Decimal{} = b) do
    Decimal.add(a, b)
  end

  @doc """
  Subtract two Decimal values.

  ## Examples

      iex> RulesEngine.Calculators.decimal_subtract(Decimal.new("5.00"), Decimal.new("2.25"))
      Decimal.new("2.75")
  """
  @spec decimal_subtract(Decimal.t(), Decimal.t()) :: Decimal.t()
  def decimal_subtract(%Decimal{} = a, %Decimal{} = b) do
    Decimal.sub(a, b)
  end

  @doc """
  Multiply two Decimal values.

  ## Examples

      iex> RulesEngine.Calculators.decimal_multiply(Decimal.new("2.50"), Decimal.new("3.00"))
      Decimal.new("7.50")
  """
  @spec decimal_multiply(Decimal.t(), Decimal.t()) :: Decimal.t()
  def decimal_multiply(%Decimal{} = a, %Decimal{} = b) do
    Decimal.mult(a, b)
    |> Decimal.round(2)
  end

  @doc """
  Convenience function to create a Decimal from string literal.

  ## Examples

      iex> RulesEngine.Calculators.dec("12.50")
      Decimal.new("12.50")

      iex> RulesEngine.Calculators.dec("0")
      Decimal.new("0")
  """
  @spec dec(String.t()) :: Decimal.t()
  def dec(value) when is_binary(value) do
    Decimal.new(value)
  end

  # Private helper to find max of two DateTimes
  defp datetime_max(%DateTime{} = a, %DateTime{} = b) do
    case DateTime.compare(a, b) do
      :gt -> a
      _ -> b
    end
  end

  # Private helper to find min of two DateTimes
  defp datetime_min(%DateTime{} = a, %DateTime{} = b) do
    case DateTime.compare(a, b) do
      :lt -> a
      _ -> b
    end
  end
end
