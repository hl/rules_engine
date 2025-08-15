defmodule RulesEngine.Engine.AlphaMemory do
  @moduledoc """
  Alpha Memory stores facts that match specific single-fact patterns.

  Each alpha memory corresponds to a specific pattern in the compiled
  RETE network and maintains an indexed set of facts that satisfy
  all the alpha tests for that pattern.
  """

  defstruct [
    # Unique identifier for this memory
    :memory_id,
    # The pattern this memory matches
    :pattern,
    # MapSet of fact IDs that match
    :facts,
    # Hash indexes for efficient lookup
    :indexes,
    # Compiled test functions
    :test_chain,
    :created_at
  ]

  @type t :: %__MODULE__{
          memory_id: term(),
          pattern: map(),
          facts: term(),
          indexes: map(),
          test_chain: list(),
          created_at: term()
        }

  @doc """
  Create new alpha memory for a pattern.
  """
  @spec new(term(), map(), list()) :: t()
  def new(memory_id, pattern, test_chain \\ []) do
    %__MODULE__{
      memory_id: memory_id,
      pattern: pattern,
      facts: MapSet.new(),
      indexes: %{},
      test_chain: test_chain,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Add a fact to this alpha memory if it matches the pattern.
  """
  @spec add_fact(t(), fact_id :: term(), fact :: map()) :: {t(), boolean()}
  def add_fact(%__MODULE__{} = memory, fact_id, fact) do
    if matches_pattern?(memory, fact) do
      new_facts = MapSet.put(memory.facts, fact_id)
      new_indexes = update_indexes(memory.indexes, fact_id, fact)

      new_memory = %{memory | facts: new_facts, indexes: new_indexes}

      {new_memory, true}
    else
      {memory, false}
    end
  end

  @doc """
  Remove a fact from this alpha memory.
  """
  @spec remove_fact(t(), fact_id :: term(), fact :: map()) :: t()
  def remove_fact(%__MODULE__{} = memory, fact_id, fact) do
    if MapSet.member?(memory.facts, fact_id) do
      new_facts = MapSet.delete(memory.facts, fact_id)
      new_indexes = remove_from_indexes(memory.indexes, fact_id, fact)

      %{memory | facts: new_facts, indexes: new_indexes}
    else
      memory
    end
  end

  @doc """
  Get all facts in this alpha memory.
  """
  @spec get_facts(t()) :: MapSet.t()
  def get_facts(%__MODULE__{} = memory) do
    memory.facts
  end

  @doc """
  Get facts by index key for efficient joins.
  """
  @spec get_facts_by_index(t(), index_key :: term(), value :: term()) :: MapSet.t()
  def get_facts_by_index(%__MODULE__{} = memory, index_key, value) do
    memory.indexes
    |> Map.get(index_key, %{})
    |> Map.get(value, MapSet.new())
  end

  @doc """
  Check if memory is empty.
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = memory) do
    MapSet.size(memory.facts) == 0
  end

  @doc """
  Get size of memory.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = memory) do
    MapSet.size(memory.facts)
  end

  # Private Implementation

  defp matches_pattern?(memory, fact) do
    # Apply all test functions in the chain
    Enum.all?(memory.test_chain, fn test_fn ->
      test_fn.(fact)
    end)
  end

  defp update_indexes(indexes, fact_id, fact) do
    # Create indexes based on discriminating keys from pattern
    indexes
    |> update_type_index(fact_id, fact)
    |> update_field_indexes(fact_id, fact)
  end

  defp update_type_index(indexes, fact_id, fact) do
    type = Map.get(fact, :type)

    Map.update(indexes, :type, %{type => MapSet.new([fact_id])}, fn type_index ->
      Map.update(type_index, type, MapSet.new([fact_id]), &MapSet.put(&1, fact_id))
    end)
  end

  defp update_field_indexes(indexes, fact_id, fact) do
    # Create field-specific indexes for common query patterns
    Enum.reduce(fact, indexes, fn {field, value}, acc ->
      case field do
        # Already indexed above
        :type -> acc
        :id -> update_field_index(acc, :id, value, fact_id)
        field when is_atom(field) -> update_field_index(acc, field, value, fact_id)
        _ -> acc
      end
    end)
  end

  defp update_field_index(indexes, field, value, fact_id) do
    index_key = {:field, field}

    Map.update(indexes, index_key, %{value => MapSet.new([fact_id])}, fn field_index ->
      Map.update(field_index, value, MapSet.new([fact_id]), &MapSet.put(&1, fact_id))
    end)
  end

  defp remove_from_indexes(indexes, fact_id, fact) do
    type = Map.get(fact, :type)

    Map.update(indexes, :type, %{}, fn type_index ->
      Map.update(type_index, type, MapSet.new(), &MapSet.delete(&1, fact_id))
    end)
  end
end
