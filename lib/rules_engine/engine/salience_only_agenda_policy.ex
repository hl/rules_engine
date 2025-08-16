defmodule RulesEngine.Engine.SalienceOnlyAgendaPolicy do
  @moduledoc """
  Salience-only agenda policy.

  Orders activations by salience only, with lexical rule_id tie-breaking.
  Ignores recency and specificity, useful for priority-driven systems
  where timing shouldn't affect rule execution order.
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
      # Equal salience: lexical production_id tie-breaking for determinism
      act1.production_id < act2.production_id -> true
      # Default to false for equal priority
      true -> false
    end
  end

  @doc """
  Get policy name for debugging.
  """
  @impl true
  def name, do: "salience_only"

  @doc """
  Get policy description.
  """
  @impl true
  def description do
    "Orders by salience (high to low), then lexical production_id"
  end
end
