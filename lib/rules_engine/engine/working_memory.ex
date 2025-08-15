defmodule RulesEngine.Engine.WorkingMemory do
  @moduledoc """
  Working Memory (WM) implementation for storing and indexing facts.

  Maintains facts by ID and type, with support for partitioning and
  efficient lookup patterns. Handles assert/modify/retract operations
  and propagates changes through the RETE network.
  """

  defstruct [
    # %{id => fact}
    :facts,
    # %{type => MapSet[id]}
    :type_index,
    # %{memory_id => AlphaMemory}
    :alpha_memories,
    # %{memory_id => BetaMemory}
    :beta_memories,
    # %{node_id => TokenTable}
    :token_tables,
    :partition_count
  ]

  @type fact :: map()
  @type fact_id :: term()
  @type fact_type :: atom() | binary()

  @type t :: %__MODULE__{
          facts: %{fact_id() => fact()},
          type_index: %{fact_type() => MapSet.t()},
          alpha_memories: %{term() => AlphaMemory.t()},
          beta_memories: %{term() => BetaMemory.t()},
          token_tables: %{term() => TokenTable.t()},
          partition_count: pos_integer()
        }

  alias RulesEngine.Engine.{AlphaMemory, BetaMemory, TokenTable}

  @doc """
  Create new working memory with specified partition count.
  """
  @spec new(partition_count :: pos_integer()) :: t()
  def new(partition_count \\ 1) do
    %__MODULE__{
      facts: %{},
      type_index: %{},
      alpha_memories: %{},
      beta_memories: %{},
      token_tables: %{},
      partition_count: partition_count
    }
  end

  @doc """
  Assert facts into working memory and propagate through network.
  """
  @spec assert_facts(state :: map(), facts :: [fact()]) :: {map(), [fact()]}
  def assert_facts(state, facts) do
    wm = state.working_memory

    # Add facts to working memory
    {new_wm, _} =
      Enum.reduce(facts, {wm, []}, fn fact, {wm_acc, derived_acc} ->
        {updated_wm, derived} = assert_fact(wm_acc, fact)
        {updated_wm, derived_acc ++ derived}
      end)

    new_state = %{state | working_memory: new_wm}

    # TODO: Propagate through alpha network
    # This would trigger alpha memory updates and beta network propagation

    # No derived facts yet
    {new_state, []}
  end

  @doc """
  Retract facts from working memory by ID.
  """
  @spec retract_facts(state :: map(), ids :: [fact_id()]) :: {map(), [fact()]}
  def retract_facts(state, ids) do
    wm = state.working_memory

    # Collect facts being retracted
    retracted =
      Enum.map(ids, &Map.get(wm.facts, &1))
      |> Enum.filter(&(&1 != nil))

    # Remove from working memory
    new_wm = Enum.reduce(ids, wm, &retract_fact(&2, &1))

    new_state = %{state | working_memory: new_wm}

    # TODO: Propagate retractions through network

    {new_state, retracted}
  end

  @doc """
  Get facts by type.
  """
  @spec facts_by_type(t(), fact_type()) :: [fact()]
  def facts_by_type(%__MODULE__{} = wm, type) do
    case Map.get(wm.type_index, type) do
      nil ->
        []

      ids ->
        ids
        |> Enum.map(&Map.get(wm.facts, &1))
        |> Enum.filter(&(&1 != nil))
    end
  end

  @doc """
  Get fact by ID.
  """
  @spec get_fact(t(), fact_id()) :: fact() | nil
  def get_fact(%__MODULE__{} = wm, id) do
    Map.get(wm.facts, id)
  end

  @doc """
  Count total facts in working memory.
  """
  @spec count_facts(t()) :: non_neg_integer()
  def count_facts(%__MODULE__{} = wm) do
    map_size(wm.facts)
  end

  @doc """
  List all fact types with counts.
  """
  @spec type_counts(t()) :: %{fact_type() => non_neg_integer()}
  def type_counts(%__MODULE__{} = wm) do
    wm.type_index
    |> Enum.map(fn {type, ids} -> {type, MapSet.size(ids)} end)
    |> Enum.into(%{})
  end

  @doc """
  Create snapshot of working memory state.
  """
  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = wm) do
    %{
      facts: wm.facts,
      type_counts: type_counts(wm),
      total_facts: count_facts(wm),
      alpha_memory_count: map_size(wm.alpha_memories),
      beta_memory_count: map_size(wm.beta_memories)
    }
  end

  # Private Implementation

  defp assert_fact(%__MODULE__{} = wm, fact) do
    id = Map.get(fact, :id)
    type = Map.get(fact, :type)

    unless id && type do
      raise ArgumentError, "Fact must have :id and :type fields: #{inspect(fact)}"
    end

    # Add to facts map
    new_facts = Map.put(wm.facts, id, fact)

    # Update type index
    new_type_index = Map.update(wm.type_index, type, MapSet.new([id]), &MapSet.put(&1, id))

    new_wm = %{wm | facts: new_facts, type_index: new_type_index}

    # TODO: Propagate through alpha memories
    derived_facts = []

    {new_wm, derived_facts}
  end

  defp retract_fact(%__MODULE__{} = wm, id) do
    case Map.get(wm.facts, id) do
      nil ->
        # Fact doesn't exist, no-op
        wm

      fact ->
        type = Map.get(fact, :type)

        # Remove from facts map
        new_facts = Map.delete(wm.facts, id)

        # Update type index
        new_type_index = Map.update(wm.type_index, type, MapSet.new(), &MapSet.delete(&1, id))

        # Clean up empty type entries
        new_type_index =
          if MapSet.size(Map.get(new_type_index, type, MapSet.new())) == 0 do
            Map.delete(new_type_index, type)
          else
            new_type_index
          end

        %{wm | facts: new_facts, type_index: new_type_index}
    end
  end
end
