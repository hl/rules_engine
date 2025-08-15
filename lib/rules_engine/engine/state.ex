defmodule RulesEngine.Engine.State do
  @moduledoc """
  Engine state structure containing all runtime data.

  Manages working memory, network state, agenda, and configuration
  for a single tenant engine instance.
  """

  alias RulesEngine.Engine.{WorkingMemory, Agenda, Network, Tracing}

  defstruct [
    :tenant_key,
    :network,
    :working_memory,
    :agenda,
    :fire_limit,
    :partition_count,
    :tracing_enabled,
    :tracer,
    :refraction_store,
    :started_at
  ]

  @type t :: %__MODULE__{
          tenant_key: term(),
          network: Network.t(),
          working_memory: WorkingMemory.t(),
          agenda: Agenda.t(),
          fire_limit: pos_integer(),
          partition_count: pos_integer(),
          tracing_enabled: boolean(),
          tracer: Tracing.t() | nil,
          refraction_store: MapSet.t(),
          started_at: DateTime.t()
        }

  @doc """
  Create new engine state with compiled network.
  """
  @spec new(tenant_key :: term(), network :: map(), opts :: keyword()) :: t()
  def new(tenant_key, network, opts) do
    fire_limit = Keyword.get(opts, :fire_limit, 1000)
    partition_count = Keyword.get(opts, :partition_count, 1)
    tracing_enabled = Keyword.get(opts, :trace, false)

    %__MODULE__{
      tenant_key: tenant_key,
      network: Network.new(network),
      working_memory: WorkingMemory.new(partition_count),
      agenda: Agenda.new(opts),
      fire_limit: fire_limit,
      partition_count: partition_count,
      tracing_enabled: tracing_enabled,
      tracer: if(tracing_enabled, do: Tracing.new(), else: nil),
      refraction_store: MapSet.new(),
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Reset state to initial conditions while preserving network.
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = state) do
    %{
      state
      | working_memory: WorkingMemory.new(state.partition_count),
        agenda: Agenda.new([]),
        refraction_store: MapSet.new()
    }
  end

  @doc """
  Create snapshot of current state for persistence.
  """
  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = state) do
    %{
      tenant_key: state.tenant_key,
      working_memory: WorkingMemory.snapshot(state.working_memory),
      agenda: Agenda.snapshot(state.agenda),
      refraction_store: MapSet.to_list(state.refraction_store),
      network_version: Network.version(state.network),
      created_at: DateTime.utc_now()
    }
  end
end
