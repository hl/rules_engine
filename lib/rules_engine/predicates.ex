defmodule RulesEngine.Predicates do
  @moduledoc """
  Registry of supported predicate operations and basic metadata.
  """

  @supported ~w(== != > >= < <= in not_in between overlap starts_with contains before after size_eq size_gt exists not_exists)a

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
  """
  @spec selectivity_hint(atom()) :: float()
  def selectivity_hint(:==), do: 0.01
  def selectivity_hint(:in), do: 0.1
  def selectivity_hint(:between), do: 0.2
  def selectivity_hint(:starts_with), do: 0.2
  def selectivity_hint(:contains), do: 0.3
  def selectivity_hint(_), do: 0.5

  @doc """
  Return simple type expectations for ops.
  - For :before/:after, at least one side must be datetime-like
  - For :size_* ops, left must be a collection and right numeric
  """
  @spec expectations(atom()) :: map()
  def expectations(:before), do: %{datetime_required?: true}
  def expectations(:after), do: %{datetime_required?: true}
  def expectations(:size_eq), do: %{collection_left?: true, numeric_right?: true}
  def expectations(:size_gt), do: %{collection_left?: true, numeric_right?: true}
  def expectations(_), do: %{}
end
