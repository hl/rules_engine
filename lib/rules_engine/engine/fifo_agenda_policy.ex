defmodule RulesEngine.Engine.FifoAgendaPolicy do
  @moduledoc """
  FIFO agenda policy - first in, first out ordering.

  Orders activations by insertion time only (oldest first).
  Useful for applications requiring strict temporal ordering
  regardless of rule priority.
  """

  @behaviour RulesEngine.Engine.AgendaPolicy

  alias RulesEngine.Engine.Activation

  @doc """
  Compare two activations for priority ordering.

  Returns true if activation1 should fire before activation2.
  """
  @impl true
  def compare(%Activation{} = act1, %Activation{} = act2) do
    # Older activations fire first (FIFO)
    DateTime.compare(act1.inserted_at, act2.inserted_at) == :lt
  end

  @doc """
  Get policy name for debugging.
  """
  @impl true
  def name, do: "fifo"

  @doc """
  Get policy description.
  """
  @impl true
  def description do
    "Orders by insertion time (FIFO - oldest first)"
  end
end
