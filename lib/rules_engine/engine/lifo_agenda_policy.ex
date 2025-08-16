defmodule RulesEngine.Engine.LifoAgendaPolicy do
  @moduledoc """
  LIFO agenda policy - last in, first out ordering.

  Orders activations by insertion time (newest first).
  Useful for applications prioritising recent rule activations,
  similar to stack-based processing.
  """

  @behaviour RulesEngine.Engine.AgendaPolicy

  alias RulesEngine.Engine.Activation

  @doc """
  Compare two activations for priority ordering.

  Returns true if activation1 should fire before activation2.
  """
  @impl true
  def compare(%Activation{} = act1, %Activation{} = act2) do
    # Newer activations fire first (LIFO)
    DateTime.compare(act1.inserted_at, act2.inserted_at) == :gt
  end

  @doc """
  Get policy name for debugging.
  """
  @impl true
  def name, do: "lifo"

  @doc """
  Get policy description.
  """
  @impl true
  def description do
    "Orders by insertion time (LIFO - newest first)"
  end
end
