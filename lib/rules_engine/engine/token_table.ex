defmodule RulesEngine.Engine.TokenTable do
  @moduledoc """
  Token Table stores propagation state for network nodes.

  Each node in the RETE network has an associated token table
  that tracks which tokens have passed through it, enabling
  efficient incremental maintenance during fact changes.
  """

  alias RulesEngine.Engine.Token

  defstruct [
    # Associated network node ID
    :node_id,
    # MapSet of tokens that passed through
    :tokens,
    # Child nodes to propagate to
    :children,
    # :join, :not, :exists, :accumulate, :production
    :node_type,
    :created_at
  ]

  @type node_type :: :join | :not | :exists | :accumulate | :production
  @type node_id :: term()

  @type t :: %__MODULE__{
          node_id: term(),
          tokens: term(),
          children: list(),
          node_type: atom(),
          created_at: term()
        }

  @doc """
  Create new token table for a network node.
  """
  @spec new(node_id(), node_type(), children :: [node_id()]) :: t()
  def new(node_id, node_type, children \\ []) do
    %__MODULE__{
      node_id: node_id,
      tokens: MapSet.new(),
      children: children,
      node_type: node_type,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Add a token to the table.
  """
  @spec add_token(t(), Token.t()) :: t()
  def add_token(%__MODULE__{} = table, %Token{} = token) do
    %{table | tokens: MapSet.put(table.tokens, token)}
  end

  @doc """
  Remove a token from the table.
  """
  @spec remove_token(t(), Token.t()) :: t()
  def remove_token(%__MODULE__{} = table, %Token{} = token) do
    %{table | tokens: MapSet.delete(table.tokens, token)}
  end

  @doc """
  Check if table contains a token.
  """
  @spec has_token?(t(), Token.t()) :: boolean()
  def has_token?(%__MODULE__{} = table, %Token{} = token) do
    MapSet.member?(table.tokens, token)
  end

  @doc """
  Get all tokens in the table.
  """
  @spec get_tokens(t()) :: MapSet.t(Token.t())
  def get_tokens(%__MODULE__{} = table) do
    table.tokens
  end

  @doc """
  Find tokens that contain a specific WME (for retraction).
  """
  @spec tokens_with_wme(t(), fact_id :: term()) :: [Token.t()]
  def tokens_with_wme(%__MODULE__{} = table, wme) do
    table.tokens
    |> Enum.filter(&Token.has_wme?(&1, wme))
  end

  @doc """
  Clear all tokens from the table.
  """
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = table) do
    %{table | tokens: MapSet.new()}
  end

  @doc """
  Get table statistics.
  """
  @spec stats(t()) :: map()
  def stats(%__MODULE__{} = table) do
    %{
      node_id: table.node_id,
      node_type: table.node_type,
      token_count: MapSet.size(table.tokens),
      children_count: length(table.children),
      created_at: table.created_at
    }
  end

  @doc """
  Check if table is empty.
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = table) do
    MapSet.size(table.tokens) == 0
  end
end
