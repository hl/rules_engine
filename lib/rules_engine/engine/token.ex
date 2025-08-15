defmodule RulesEngine.Engine.Token do
  @moduledoc """
  Token represents a partial match in the RETE network.

  Tokens carry bindings from matched facts and WME references
  for efficient joins and retractions. They are immutable
  structures passed between beta nodes.
  """

  defstruct [
    # %{binding_name => value}
    :bindings,
    # [fact_id] - ordered list of fact IDs
    :wmes,
    # Pre-computed hash for efficient comparison
    :hash,
    # Optional lineage information
    :provenance,
    :created_at
  ]

  @type binding_name :: atom()
  @type binding_value :: term()
  @type fact_id :: term()

  @type t :: %__MODULE__{
          bindings: map(),
          wmes: list(),
          hash: integer(),
          provenance: term(),
          created_at: term()
        }

  @doc """
  Create a new token with bindings and WMEs.
  """
  @spec new(bindings :: map(), wmes :: [fact_id()], provenance :: map() | nil) :: t()
  def new(bindings \\ %{}, wmes \\ [], provenance \\ nil) do
    token = %__MODULE__{
      bindings: bindings,
      wmes: wmes,
      hash: compute_hash(bindings, wmes),
      provenance: provenance,
      created_at: DateTime.utc_now()
    }

    token
  end

  @doc """
  Extend a token with additional bindings and WME.
  """
  @spec extend(t(), new_bindings :: map(), wme :: fact_id()) :: t()
  def extend(%__MODULE__{} = token, new_bindings, wme) do
    merged_bindings = Map.merge(token.bindings, new_bindings)
    extended_wmes = token.wmes ++ [wme]

    %{
      token
      | bindings: merged_bindings,
        wmes: extended_wmes,
        hash: compute_hash(merged_bindings, extended_wmes)
    }
  end

  @doc """
  Get binding value by name.
  """
  @spec get_binding(t(), binding_name()) :: {:ok, binding_value()} | :error
  def get_binding(%__MODULE__{} = token, binding_name) do
    case Map.fetch(token.bindings, binding_name) do
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  end

  @doc """
  Check if token has a specific binding.
  """
  @spec has_binding?(t(), binding_name()) :: boolean()
  def has_binding?(%__MODULE__{} = token, binding_name) do
    Map.has_key?(token.bindings, binding_name)
  end

  @doc """
  Get all binding names in token.
  """
  @spec binding_names(t()) :: [binding_name()]
  def binding_names(%__MODULE__{} = token) do
    Map.keys(token.bindings)
  end

  @doc """
  Get all bindings from token.
  """
  @spec bindings(t()) :: %{binding_name() => binding_value()}
  def bindings(%__MODULE__{} = token) do
    token.bindings
  end

  @doc """
  Get WMEs (fact IDs) in token.
  """
  @spec get_wmes(t()) :: [fact_id()]
  def get_wmes(%__MODULE__{} = token) do
    token.wmes
  end

  @doc """
  Check if token contains a specific WME.
  """
  @spec has_wme?(t(), fact_id()) :: boolean()
  def has_wme?(%__MODULE__{} = token, wme) do
    wme in token.wmes
  end

  @doc """
  Create signature for refraction checking.

  The signature uniquely identifies the combination of facts
  that created this token, ignoring binding values.
  """
  @spec signature(t()) :: term()
  def signature(%__MODULE__{} = token) do
    # Sort WMEs for consistent signature regardless of join order
    sorted_wmes = Enum.sort(token.wmes)
    binding_keys = Enum.sort(Map.keys(token.bindings))

    {sorted_wmes, binding_keys}
  end

  @doc """
  Check if two tokens are compatible for joining.

  Tokens are compatible if they don't have conflicting bindings
  for the same variable names.
  """
  @spec compatible?(t(), t()) :: boolean()
  def compatible?(%__MODULE__{} = token1, %__MODULE__{} = token2) do
    common_bindings =
      Map.keys(token1.bindings) -- (Map.keys(token1.bindings) -- Map.keys(token2.bindings))

    Enum.all?(common_bindings, fn key ->
      Map.get(token1.bindings, key) == Map.get(token2.bindings, key)
    end)
  end

  # Private Implementation

  defp compute_hash(bindings, wmes) do
    # Create stable hash from bindings and WMEs
    content = {Enum.sort(Map.to_list(bindings)), Enum.sort(wmes)}
    :erlang.phash2(content)
  end
end
