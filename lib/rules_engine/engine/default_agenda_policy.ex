defmodule RulesEngine.Engine.DefaultAgendaPolicy do
  @moduledoc """
  Default agenda policy implementing salience + recency + specificity ordering.

  Orders activations by:
  1. Salience (higher first)
  2. Specificity (more patterns first) 
  3. Recency (LIFO - more recent first)

  This provides predictable, deterministic rule firing order.
  """

  @behaviour RulesEngine.Engine.AgendaPolicy

  alias RulesEngine.Engine.Activation

  @doc """
  Compare two activations for priority ordering.

  Returns true if activation1 should fire before activation2.
  """
  @impl true
  def compare(%Activation{} = act1, %Activation{} = act2) do
    cond do
      # Higher salience wins
      act1.salience > act2.salience -> true
      act1.salience < act2.salience -> false
      # Within same salience, higher specificity wins
      act1.specificity > act2.specificity -> true
      act1.specificity < act2.specificity -> false
      # Within same salience and specificity, more recent wins (LIFO)
      DateTime.compare(act1.inserted_at, act2.inserted_at) == :gt -> true
      # Default to false for equal priority
      true -> false
    end
  end

  @doc """
  Get policy name for debugging.
  """
  @impl true
  def name, do: "default_salience_recency_specificity"

  @doc """
  Get policy description.
  """
  @impl true
  def description do
    "Orders by salience (high to low), then specificity (high to low), then recency (LIFO)"
  end
end
