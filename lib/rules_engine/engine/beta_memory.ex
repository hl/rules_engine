defmodule RulesEngine.Engine.BetaMemory do
  @moduledoc """
  Beta Memory stores partial matches (tokens) from join operations.

  Beta memories sit on the left side of join nodes and store
  tokens representing partial matches from earlier patterns
  in the rule. They maintain indexes for efficient hash-joins.
  """

  alias RulesEngine.Engine.Token

  defstruct [
    # Unique identifier for this memory
    :memory_id,
    # MapSet of tokens
    :tokens,
    # Hash indexes by binding keys for joins
    :hash_indexes,
    # Keys used for joining
    :join_keys,
    :created_at
  ]

  @type t :: %__MODULE__{
          memory_id: term(),
          tokens: term(),
          hash_indexes: map(),
          join_keys: list(),
          created_at: term()
        }

  @doc """
  Create new beta memory with join keys for indexing.
  """
  @spec new(memory_id :: term(), join_keys :: [atom()]) :: t()
  def new(memory_id, join_keys \\ []) do
    %__MODULE__{
      memory_id: memory_id,
      tokens: MapSet.new(),
      hash_indexes: %{},
      join_keys: join_keys,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Add a token to this beta memory.
  """
  @spec add_token(t(), Token.t()) :: t()
  def add_token(%__MODULE__{} = memory, %Token{} = token) do
    new_tokens = MapSet.put(memory.tokens, token)
    new_indexes = update_indexes(memory.hash_indexes, memory.join_keys, token, :add)

    %{memory | tokens: new_tokens, hash_indexes: new_indexes}
  end

  @doc """
  Remove a token from this beta memory.
  """
  @spec remove_token(t(), Token.t()) :: t()
  def remove_token(%__MODULE__{} = memory, %Token{} = token) do
    if MapSet.member?(memory.tokens, token) do
      new_tokens = MapSet.delete(memory.tokens, token)
      new_indexes = update_indexes(memory.hash_indexes, memory.join_keys, token, :remove)

      %{memory | tokens: new_tokens, hash_indexes: new_indexes}
    else
      memory
    end
  end

  @doc """
  Get all tokens in this beta memory.
  """
  @spec get_tokens(t()) :: MapSet.t(Token.t())
  def get_tokens(%__MODULE__{} = memory) do
    memory.tokens
  end

  @doc """
  Get tokens by hash key value for efficient joins.
  """
  @spec get_tokens_by_key(t(), key :: atom(), value :: term()) :: MapSet.t(Token.t())
  def get_tokens_by_key(%__MODULE__{} = memory, key, value) do
    memory.hash_indexes
    |> Map.get(key, %{})
    |> Map.get(value, MapSet.new())
  end

  @doc """
  Check if memory is empty.
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = memory) do
    MapSet.size(memory.tokens) == 0
  end

  @doc """
  Get size of memory.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = memory) do
    MapSet.size(memory.tokens)
  end

  # Private Implementation

  defp update_indexes(indexes, join_keys, %Token{} = token, operation) do
    Enum.reduce(join_keys, indexes, fn key, acc_indexes ->
      case Token.get_binding(token, key) do
        {:ok, value} ->
          update_index_for_key(acc_indexes, key, value, token, operation)

        :error ->
          # Skip if binding not found
          acc_indexes
      end
    end)
  end

  defp update_index_for_key(indexes, key, value, token, :add) do
    Map.update(indexes, key, %{value => MapSet.new([token])}, fn key_index ->
      Map.update(key_index, value, MapSet.new([token]), &MapSet.put(&1, token))
    end)
  end

  defp update_index_for_key(indexes, key, value, token, :remove) do
    Map.update(indexes, key, %{}, fn key_index ->
      Map.update(key_index, value, MapSet.new(), &MapSet.delete(&1, token))
    end)
  end
end
