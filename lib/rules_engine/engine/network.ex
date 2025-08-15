defmodule RulesEngine.Engine.Network do
  @moduledoc """
  Network represents the compiled RETE network structure.

  Contains the immutable network topology with nodes, edges,
  and metadata needed for fact propagation and rule execution.
  """

  defstruct [
    # Network version/hash
    :version,
    # %{node_id => alpha_node}
    :alpha_nodes,
    # %{node_id => beta_node}
    :beta_nodes,
    # %{node_id => production_node}
    :production_nodes,
    # %{from_node => [to_node]}
    :edges,
    # %{fact_type => [alpha_node_id]}
    :entry_points,
    # Compilation metadata
    :metadata,
    :created_at
  ]

  @type node_id :: term()
  @type alpha_node :: map()
  @type beta_node :: map()
  @type production_node :: map()

  @type t :: %__MODULE__{
          version: binary(),
          alpha_nodes: %{node_id() => alpha_node()},
          beta_nodes: %{node_id() => beta_node()},
          production_nodes: %{node_id() => production_node()},
          edges: %{node_id() => [node_id()]},
          entry_points: %{atom() => [node_id()]},
          metadata: map(),
          created_at: DateTime.t()
        }

  @doc """
  Create network from compiled IR.
  """
  @spec new(ir :: map()) :: t()
  def new(ir) when is_map(ir) do
    version = compute_version(ir)

    %__MODULE__{
      version: version,
      alpha_nodes: extract_alpha_nodes(ir),
      beta_nodes: extract_beta_nodes(ir),
      production_nodes: extract_production_nodes(ir),
      edges: extract_edges(ir),
      entry_points: extract_entry_points(ir),
      metadata: Map.get(ir, :metadata, %{}),
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Get network version for caching and comparison.
  """
  @spec version(t()) :: binary()
  def version(%__MODULE__{} = network) do
    network.version
  end

  @doc """
  Get alpha nodes for a specific fact type.
  """
  @spec alpha_entry_points(t(), fact_type :: atom()) :: [node_id()]
  def alpha_entry_points(%__MODULE__{} = network, fact_type) do
    Map.get(network.entry_points, fact_type, [])
  end

  @doc """
  Get alpha node by ID.
  """
  @spec get_alpha_node(t(), node_id()) :: alpha_node() | nil
  def get_alpha_node(%__MODULE__{} = network, node_id) do
    Map.get(network.alpha_nodes, node_id)
  end

  @doc """
  Get beta node by ID.
  """
  @spec get_beta_node(t(), node_id()) :: beta_node() | nil
  def get_beta_node(%__MODULE__{} = network, node_id) do
    Map.get(network.beta_nodes, node_id)
  end

  @doc """
  Get production node by ID.
  """
  @spec get_production_node(t(), node_id()) :: production_node() | nil
  def get_production_node(%__MODULE__{} = network, node_id) do
    Map.get(network.production_nodes, node_id)
  end

  @doc """
  Get child nodes for a given node.
  """
  @spec children(t(), node_id()) :: [node_id()]
  def children(%__MODULE__{} = network, node_id) do
    Map.get(network.edges, node_id, [])
  end

  @doc """
  Get all node IDs in the network.
  """
  @spec all_nodes(t()) :: [node_id()]
  def all_nodes(%__MODULE__{} = network) do
    alpha_ids = Map.keys(network.alpha_nodes)
    beta_ids = Map.keys(network.beta_nodes)
    production_ids = Map.keys(network.production_nodes)

    alpha_ids ++ beta_ids ++ production_ids
  end

  @doc """
  Get network statistics.
  """
  @spec stats(t()) :: map()
  def stats(%__MODULE__{} = network) do
    %{
      version: network.version,
      alpha_nodes: map_size(network.alpha_nodes),
      beta_nodes: map_size(network.beta_nodes),
      production_nodes: map_size(network.production_nodes),
      total_edges: network.edges |> Map.values() |> List.flatten() |> length(),
      entry_points: map_size(network.entry_points),
      created_at: network.created_at
    }
  end

  # Private Implementation

  defp compute_version(ir) do
    # Create stable hash of IR structure
    content = Map.take(ir, [:rules, :alpha_network, :beta_network, :productions])
    :crypto.hash(:sha256, :erlang.term_to_binary(content)) |> Base.encode16()
  end

  defp extract_alpha_nodes(ir) do
    case Map.get(ir, :alpha_network) do
      nil ->
        %{}

      alpha_network ->
        alpha_network
        |> Map.get(:nodes, [])
        |> Enum.map(fn node -> {Map.get(node, :id), node} end)
        |> Enum.into(%{})
    end
  end

  defp extract_beta_nodes(ir) do
    case Map.get(ir, :beta_network) do
      nil ->
        %{}

      beta_network ->
        beta_network
        |> Map.get(:nodes, [])
        |> Enum.map(fn node -> {Map.get(node, :id), node} end)
        |> Enum.into(%{})
    end
  end

  defp extract_production_nodes(ir) do
    case Map.get(ir, :productions) do
      nil ->
        %{}

      productions ->
        productions
        |> Enum.map(fn prod -> {Map.get(prod, :id), prod} end)
        |> Enum.into(%{})
    end
  end

  defp extract_edges(ir) do
    # Extract edges from alpha, beta, and production networks
    alpha_edges = extract_network_edges(Map.get(ir, :alpha_network, %{}))
    beta_edges = extract_network_edges(Map.get(ir, :beta_network, %{}))

    Map.merge(alpha_edges, beta_edges)
  end

  defp extract_network_edges(network) do
    network
    |> Map.get(:nodes, [])
    |> Enum.map(fn node ->
      node_id = Map.get(node, :id)
      children = Map.get(node, :children, [])
      {node_id, children}
    end)
    |> Enum.into(%{})
  end

  defp extract_entry_points(ir) do
    # Build mapping from fact types to alpha node entry points
    case Map.get(ir, :alpha_network) do
      nil ->
        %{}

      alpha_network ->
        alpha_network
        |> Map.get(:nodes, [])
        |> Enum.group_by(fn node ->
          # Extract fact type from alpha node pattern
          pattern = Map.get(node, :pattern, %{})
          Map.get(pattern, :type, :unknown)
        end)
        |> Enum.map(fn {type, nodes} ->
          node_ids = Enum.map(nodes, &Map.get(&1, :id))
          {type, node_ids}
        end)
        |> Enum.into(%{})
    end
  end
end
