defmodule RulesEngine.Predicates do
  @moduledoc """
  Registry of supported predicate operations with evaluation functions and metadata.

  Provides pure evaluation functions for predicates used in rules processing,
  along with indexability hints and selectivity estimates for query optimisation.
  """

  @supported ~w(== != > >= < <= in not_in between overlap starts_with contains before after size_eq size_gt exists not_exists ends_with matches approximately)a

  @spec supported_ops() :: [atom()]
  def supported_ops, do: @supported

  @doc """
  Whether a predicate is indexable at alpha or join nodes.
  """
  @spec indexable?(atom()) :: boolean()
  def indexable?(op) when op in [:==, :in, :between], do: true
  def indexable?(_), do: false

  @doc """
  Selectivity hint in [0.0, 1.0]; lower is more selective.

  Used by query optimiser to order predicate evaluation for best performance.
  """
  @spec selectivity_hint(atom()) :: float()
  def selectivity_hint(:==), do: 0.01
  def selectivity_hint(:in), do: 0.1
  def selectivity_hint(:between), do: 0.2
  def selectivity_hint(:starts_with), do: 0.15
  def selectivity_hint(:ends_with), do: 0.15
  def selectivity_hint(:contains), do: 0.3
  def selectivity_hint(:matches), do: 0.05
  def selectivity_hint(:before), do: 0.2
  def selectivity_hint(:after), do: 0.2
  def selectivity_hint(:approximately), do: 0.05
  def selectivity_hint(_), do: 0.5

  @doc """
  Return type expectations and validation requirements for predicates.

  Used during AST validation to catch type mismatches early.
  """
  @spec expectations(atom()) :: map()
  def expectations(:before), do: %{datetime_required?: true}
  def expectations(:after), do: %{datetime_required?: true}
  def expectations(:size_eq), do: %{collection_left?: true, numeric_right?: true}
  def expectations(:size_gt), do: %{collection_left?: true, numeric_right?: true}
  def expectations(:starts_with), do: %{string_left?: true, string_right?: true}
  def expectations(:ends_with), do: %{string_left?: true, string_right?: true}
  def expectations(:contains), do: %{string_left?: true, string_right?: true}
  def expectations(:matches), do: %{string_left?: true, regex_right?: true}
  def expectations(:approximately), do: %{numeric_left?: true, numeric_right?: true}
  def expectations(_), do: %{}

  @doc """
  Evaluate a predicate against two values.

  Returns boolean result of the predicate operation.
  Raises on invalid arguments to catch bugs early in development.

  ## Examples

      iex> RulesEngine.Predicates.evaluate(:==, "hello", "hello")
      true
      
      iex> RulesEngine.Predicates.evaluate(:starts_with, "hello world", "hello")
      true
      
      iex> RulesEngine.Predicates.evaluate(:size_gt, [1, 2, 3], 2)
      true
  """
  @spec evaluate(atom(), term(), term()) :: boolean()
  def evaluate(:==, left, right), do: left == right
  def evaluate(:!=, left, right), do: left != right
  def evaluate(:>, left, right), do: left > right
  def evaluate(:>=, left, right), do: left >= right
  def evaluate(:<, left, right), do: left < right
  def evaluate(:<=, left, right), do: left <= right

  def evaluate(:in, left, right) when is_list(right), do: left in right
  def evaluate(:not_in, left, right) when is_list(right), do: left not in right

  def evaluate(:between, value, {min_val, max_val}), do: value >= min_val and value <= max_val

  def evaluate(:overlap, {a_start, a_end}, {b_start, b_end}) do
    # Periods overlap if start of one is before end of other
    a_start < b_end and b_start < a_end
  end

  def evaluate(:starts_with, string, prefix) when is_binary(string) and is_binary(prefix) do
    String.starts_with?(string, prefix)
  end

  def evaluate(:ends_with, string, suffix) when is_binary(string) and is_binary(suffix) do
    String.ends_with?(string, suffix)
  end

  def evaluate(:contains, string, substring) when is_binary(string) and is_binary(substring) do
    String.contains?(string, substring)
  end

  def evaluate(:matches, string, %Regex{} = pattern) when is_binary(string) do
    Regex.match?(pattern, string)
  end

  def evaluate(:before, %DateTime{} = left, %DateTime{} = right) do
    DateTime.compare(left, right) == :lt
  end

  def evaluate(:after, %DateTime{} = left, %DateTime{} = right) do
    DateTime.compare(left, right) == :gt
  end

  def evaluate(:size_eq, collection, size) when is_list(collection) and is_integer(size) do
    length(collection) == size
  end

  def evaluate(:size_gt, collection, size) when is_list(collection) and is_integer(size) do
    length(collection) > size
  end

  def evaluate(:approximately, left, right) when is_number(left) and is_number(right) do
    # Default tolerance
    abs(left - right) < 0.0001
  end

  def evaluate(:approximately, %Decimal{} = left, %Decimal{} = right) do
    diff = Decimal.sub(left, right) |> Decimal.abs()
    # Default tolerance for decimals
    Decimal.compare(diff, Decimal.new("0.01")) == :lt
  end

  # For exists/not_exists, these are handled at the network level, not as predicate evaluation
  def evaluate(:exists, _left, _right),
    do: raise("exists/not_exists handled by network evaluation")

  def evaluate(:not_exists, _left, _right),
    do: raise("exists/not_exists handled by network evaluation")
end
