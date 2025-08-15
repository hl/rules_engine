defmodule RulesEngine.Helpers do
  @moduledoc """
  Pure helper functions for type conversions and validations.

  Provides safe, well-tested utilities to avoid runtime surprises in rules processing.
  All functions are pure (no side effects) and deterministic.
  """

  @doc """
  Safely convert various input types to DateTime.

  Handles string parsing, Unix timestamps, and existing DateTime values.
  Returns `{:ok, datetime}` or `{:error, reason}`.

  ## Examples

      iex> RulesEngine.Helpers.to_datetime(~U[2023-01-01 12:00:00Z])
      {:ok, ~U[2023-01-01 12:00:00Z]}

      iex> RulesEngine.Helpers.to_datetime("2023-01-01T12:00:00Z")
      {:ok, ~U[2023-01-01 12:00:00Z]}

      iex> RulesEngine.Helpers.to_datetime(1672574400)
      {:ok, ~U[2023-01-01 12:00:00Z]}
  """
  @spec to_datetime(DateTime.t() | String.t() | integer()) ::
          {:ok, DateTime.t()} | {:error, term()}
  def to_datetime(%DateTime{} = dt), do: {:ok, dt}

  def to_datetime(timestamp) when is_integer(timestamp) do
    case DateTime.from_unix(timestamp) do
      {:ok, dt} -> {:ok, dt}
      {:error, reason} -> {:error, {:unix_conversion, reason}}
    end
  end

  def to_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, reason} -> {:error, {:iso8601_parse, reason}}
    end
  end

  def to_datetime(_other), do: {:error, :invalid_datetime_input}

  @doc """
  Safely convert various input types to Decimal.

  Handles strings, integers, floats, and existing Decimal values.
  Returns `{:ok, decimal}` or `{:error, reason}`.

  ## Examples

      iex> RulesEngine.Helpers.to_decimal("12.50")
      {:ok, Decimal.new("12.50")}

      iex> RulesEngine.Helpers.to_decimal(42)
      {:ok, Decimal.new("42")}

      iex> RulesEngine.Helpers.to_decimal(3.14)
      {:ok, Decimal.new("3.14")}
  """
  @spec to_decimal(Decimal.t() | String.t() | integer() | float()) ::
          {:ok, Decimal.t()} | {:error, term()}
  def to_decimal(%Decimal{} = d), do: {:ok, d}

  def to_decimal(value) when is_integer(value) do
    {:ok, Decimal.new(value)}
  end

  def to_decimal(value) when is_float(value) do
    {:ok, Decimal.from_float(value)}
  end

  def to_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> {:ok, decimal}
      {_decimal, _remainder} -> {:error, {:decimal_parse, :invalid_format}}
      :error -> {:error, {:decimal_parse, :invalid_input}}
    end
  end

  def to_decimal(_other), do: {:error, :invalid_decimal_input}

  @doc """
  Validate that a value is a collection (list).

  ## Examples

      iex> RulesEngine.Helpers.validate_collection([1, 2, 3])
      {:ok, [1, 2, 3]}

      iex> RulesEngine.Helpers.validate_collection("not a list")
      {:error, :not_a_collection}
  """
  @spec validate_collection(term()) :: {:ok, list()} | {:error, :not_a_collection}
  def validate_collection(value) when is_list(value), do: {:ok, value}
  def validate_collection(_), do: {:error, :not_a_collection}

  @doc """
  Validate that a value is numeric (integer or float).

  ## Examples

      iex> RulesEngine.Helpers.validate_numeric(42)
      {:ok, 42}

      iex> RulesEngine.Helpers.validate_numeric(3.14)
      {:ok, 3.14}

      iex> RulesEngine.Helpers.validate_numeric("not a number")
      {:error, :not_numeric}
  """
  @spec validate_numeric(term()) :: {:ok, number()} | {:error, :not_numeric}
  def validate_numeric(value) when is_number(value), do: {:ok, value}
  def validate_numeric(_), do: {:error, :not_numeric}

  @doc """
  Validate that a value is a string.

  ## Examples

      iex> RulesEngine.Helpers.validate_string("hello")
      {:ok, "hello"}

      iex> RulesEngine.Helpers.validate_string(123)
      {:error, :not_a_string}
  """
  @spec validate_string(term()) :: {:ok, String.t()} | {:error, :not_a_string}
  def validate_string(value) when is_binary(value), do: {:ok, value}
  def validate_string(_), do: {:error, :not_a_string}

  @doc """
  Safe division that handles division by zero.

  Returns `{:ok, result}` or `{:error, :division_by_zero}`.

  ## Examples

      iex> RulesEngine.Helpers.safe_divide(10, 2)
      {:ok, 5.0}

      iex> RulesEngine.Helpers.safe_divide(10, 0)
      {:error, :division_by_zero}
  """
  @spec safe_divide(number(), number()) :: {:ok, float()} | {:error, :division_by_zero}
  def safe_divide(_dividend, 0), do: {:error, :division_by_zero}
  def safe_divide(_dividend, divisor) when divisor == +0.0, do: {:error, :division_by_zero}
  def safe_divide(_dividend, divisor) when divisor == -0.0, do: {:error, :division_by_zero}

  def safe_divide(dividend, divisor) when is_number(dividend) and is_number(divisor) do
    {:ok, dividend / divisor}
  end

  @doc """
  Safe division for Decimals that handles division by zero.

  Returns `{:ok, result}` or `{:error, :division_by_zero}`.

  ## Examples

      iex> RulesEngine.Helpers.safe_decimal_divide(Decimal.new("10"), Decimal.new("2"))
      {:ok, Decimal.new("5")}

      iex> RulesEngine.Helpers.safe_decimal_divide(Decimal.new("10"), Decimal.new("0"))
      {:error, :division_by_zero}
  """
  @spec safe_decimal_divide(Decimal.t(), Decimal.t()) ::
          {:ok, Decimal.t()} | {:error, :division_by_zero}
  def safe_decimal_divide(%Decimal{} = dividend, %Decimal{} = divisor) do
    if Decimal.equal?(divisor, Decimal.new(0)) do
      {:error, :division_by_zero}
    else
      {:ok, Decimal.div(dividend, divisor)}
    end
  end

  @doc """
  Clamp a numeric value between min and max bounds.

  ## Examples

      iex> RulesEngine.Helpers.clamp(5, 1, 10)
      5

      iex> RulesEngine.Helpers.clamp(-5, 1, 10)
      1

      iex> RulesEngine.Helpers.clamp(15, 1, 10)
      10
  """
  @spec clamp(number(), number(), number()) :: number()
  def clamp(value, min_val, _max_val) when value < min_val, do: min_val
  def clamp(value, _min_val, max_val) when value > max_val, do: max_val
  def clamp(value, _min_val, _max_val), do: value

  @doc """
  Clamp a Decimal value between min and max bounds.

  ## Examples

      iex> RulesEngine.Helpers.decimal_clamp(Decimal.new("5"), Decimal.new("1"), Decimal.new("10"))
      Decimal.new("5")

      iex> RulesEngine.Helpers.decimal_clamp(Decimal.new("-5"), Decimal.new("1"), Decimal.new("10"))
      Decimal.new("1")
  """
  @spec decimal_clamp(Decimal.t(), Decimal.t(), Decimal.t()) :: Decimal.t()
  def decimal_clamp(%Decimal{} = value, %Decimal{} = min_val, %Decimal{} = max_val) do
    cond do
      Decimal.compare(value, min_val) == :lt -> min_val
      Decimal.compare(value, max_val) == :gt -> max_val
      true -> value
    end
  end

  @doc """
  Round a number to specified decimal places.

  ## Examples

      iex> RulesEngine.Helpers.round_to(3.14159, 2)
      3.14

      iex> RulesEngine.Helpers.round_to(3.14159, 0)
      3.0
  """
  @spec round_to(number(), non_neg_integer()) :: float()
  def round_to(value, places) when is_number(value) and is_integer(places) and places >= 0 do
    multiplier = :math.pow(10, places)
    Float.round(value * multiplier) / multiplier
  end

  @doc """
  Normalize a string by trimming whitespace and converting to lowercase.

  Useful for case-insensitive string comparisons.

  ## Examples

      iex> RulesEngine.Helpers.normalize_string("  Hello World  ")
      "hello world"

      iex> RulesEngine.Helpers.normalize_string("Test")
      "test"
  """
  @spec normalize_string(String.t()) :: String.t()
  def normalize_string(str) when is_binary(str) do
    str
    |> String.trim()
    |> String.downcase()
  end

  @doc """
  Check if a value is nil or empty.

  Works with strings, lists, maps, and nil values.

  ## Examples

      iex> RulesEngine.Helpers.empty?(nil)
      true

      iex> RulesEngine.Helpers.empty?("")
      true

      iex> RulesEngine.Helpers.empty?([])
      true

      iex> RulesEngine.Helpers.empty?("hello")
      false
  """
  @spec empty?(term()) :: boolean()
  def empty?(nil), do: true
  def empty?(""), do: true
  def empty?([]), do: true
  def empty?(map) when is_map(map), do: map_size(map) == 0
  def empty?(_), do: false
end
