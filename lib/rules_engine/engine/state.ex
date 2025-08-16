defmodule RulesEngine.Engine.State do
  @moduledoc """
  Engine state structure containing all runtime data.

  Manages working memory, network state, agenda, and configuration
  for a single tenant engine instance.
  """

  alias RulesEngine.Engine.{
    Agenda,
    AgendaPolicyRegistry,
    Network,
    RefractionPolicyRegistry,
    Tracing,
    WorkingMemory
  }

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
    :refraction_policy,
    :refraction_opts,
    :started_at,
    # Memory management
    :memory_limit_bytes,
    :memory_usage_bytes,
    :memory_check_interval,
    :memory_eviction_policy,
    # Operation tracking
    :operation_count
  ]

  @type t :: %__MODULE__{
          tenant_key: term(),
          network: term(),
          working_memory: term(),
          agenda: term(),
          fire_limit: pos_integer(),
          partition_count: pos_integer(),
          tracing_enabled: boolean(),
          tracer: term(),
          refraction_store: term(),
          refraction_policy: module(),
          refraction_opts: keyword(),
          started_at: term(),
          memory_limit_bytes: pos_integer() | nil,
          memory_usage_bytes: non_neg_integer(),
          memory_check_interval: pos_integer(),
          memory_eviction_policy: atom(),
          operation_count: non_neg_integer()
        }

  @doc """
  Create new engine state with compiled network.
  """
  @spec new(tenant_key :: term(), network :: map(), opts :: keyword()) :: t()
  def new(tenant_key, network, opts) do
    fire_limit = Keyword.get(opts, :fire_limit, 1000)
    partition_count = Keyword.get(opts, :partition_count, 1)
    tracing_enabled = Keyword.get(opts, :trace, false)

    # Memory management configuration
    memory_limit_mb = Keyword.get(opts, :memory_limit_mb)
    memory_limit_bytes = if memory_limit_mb, do: memory_limit_mb * 1024 * 1024, else: nil
    # operations
    memory_check_interval = Keyword.get(opts, :memory_check_interval, 1000)
    memory_eviction_policy = Keyword.get(opts, :memory_eviction_policy, :lru)

    # Resolve agenda policy using registry
    agenda_opts = resolve_agenda_policy(opts)

    # Resolve refraction policy using registry
    {refraction_policy, refraction_opts} = resolve_refraction_policy(opts)

    %__MODULE__{
      tenant_key: tenant_key,
      network: Network.new(network),
      working_memory: WorkingMemory.new(partition_count),
      agenda: Agenda.new(agenda_opts),
      fire_limit: fire_limit,
      partition_count: partition_count,
      tracing_enabled: tracing_enabled,
      tracer: if(tracing_enabled, do: Tracing.new(), else: nil),
      refraction_store: refraction_policy.init_store(refraction_opts),
      refraction_policy: refraction_policy,
      refraction_opts: refraction_opts,
      started_at: DateTime.utc_now(),
      memory_limit_bytes: memory_limit_bytes,
      memory_usage_bytes: 0,
      memory_check_interval: memory_check_interval,
      memory_eviction_policy: memory_eviction_policy,
      operation_count: 0
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
        refraction_store: state.refraction_policy.init_store(state.refraction_opts)
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

  # Private functions

  defp resolve_agenda_policy(opts) do
    case Keyword.get(opts, :agenda_policy, :default) do
      policy_spec when is_atom(policy_spec) ->
        case AgendaPolicyRegistry.resolve_policy(policy_spec) do
          {:ok, policy_module} ->
            Keyword.put(opts, :agenda_policy, policy_module)

          {:error, :unknown_policy} ->
            # Fall back to default policy with warning
            require Logger

            Logger.warning(
              "Unknown agenda policy #{inspect(policy_spec)}, falling back to default"
            )

            Keyword.put(opts, :agenda_policy, RulesEngine.Engine.DefaultAgendaPolicy)
        end

      policy_module when is_atom(policy_module) ->
        # Already a module, pass through
        opts

      _ ->
        # Invalid policy type, fall back to default
        require Logger
        Logger.warning("Invalid agenda policy type, falling back to default")
        Keyword.put(opts, :agenda_policy, RulesEngine.Engine.DefaultAgendaPolicy)
    end
  end

  defp resolve_refraction_policy(opts) do
    policy_spec = Keyword.get(opts, :refraction_policy, :default)
    refraction_opts = Keyword.get(opts, :refraction_opts, [])

    case RefractionPolicyRegistry.resolve_policy(policy_spec) do
      {:ok, policy_module} ->
        {policy_module, refraction_opts}

      {:error, :unknown_policy} ->
        # Fall back to default policy with warning
        require Logger

        Logger.warning(
          "Unknown refraction policy #{inspect(policy_spec)}, falling back to default"
        )

        {RulesEngine.Engine.DefaultRefractionPolicy, refraction_opts}
    end
  end

  # Memory management functions

  @doc """
  Update memory usage tracking and check if limit is exceeded.
  Returns {:ok, new_state} or {:error, :memory_limit_exceeded} with suggested eviction count.
  """
  @spec update_memory_usage(t()) ::
          {:ok, t()} | {:error, :memory_limit_exceeded, non_neg_integer()}
  def update_memory_usage(%__MODULE__{memory_limit_bytes: nil} = state) do
    # No memory limit configured
    {:ok, state}
  end

  def update_memory_usage(%__MODULE__{} = state) do
    current_usage = calculate_memory_usage(state)
    updated_state = %{state | memory_usage_bytes: current_usage}

    if current_usage > state.memory_limit_bytes do
      excess_bytes = current_usage - state.memory_limit_bytes
      suggested_eviction_count = estimate_eviction_count(excess_bytes, state)
      {:error, :memory_limit_exceeded, suggested_eviction_count}
    else
      {:ok, updated_state}
    end
  end

  @doc """
  Calculate current memory usage for all engine components.
  """
  @spec calculate_memory_usage(t()) :: non_neg_integer()
  def calculate_memory_usage(%__MODULE__{} = state) do
    wm_memory = WorkingMemory.memory_usage(state.working_memory)
    agenda_memory = Agenda.memory_usage(state.agenda)
    refraction_memory = estimate_refraction_memory(state.refraction_store)

    wm_memory + agenda_memory + refraction_memory
  end

  @doc """
  Increment operation count and return updated state.
  """
  @spec increment_operation_count(t()) :: t()
  def increment_operation_count(%__MODULE__{} = state) do
    %{state | operation_count: state.operation_count + 1}
  end

  @doc """
  Check if memory usage should be evaluated based on check interval.
  """
  @spec should_check_memory?(t(), non_neg_integer()) :: boolean()
  def should_check_memory?(%__MODULE__{memory_limit_bytes: nil}, _operation_count), do: false

  def should_check_memory?(%__MODULE__{} = state, operation_count) do
    rem(operation_count, state.memory_check_interval) == 0
  end

  @doc """
  Get memory usage statistics for monitoring.
  """
  @spec memory_stats(t()) :: %{
          limit_bytes: pos_integer() | nil,
          usage_bytes: non_neg_integer(),
          usage_percentage: float(),
          facts_count: non_neg_integer(),
          agenda_size: non_neg_integer()
        }
  def memory_stats(%__MODULE__{} = state) do
    current_usage = calculate_memory_usage(state)
    facts_count = map_size(state.working_memory.facts)
    agenda_size = Agenda.size(state.agenda)

    usage_percentage =
      if state.memory_limit_bytes do
        current_usage / state.memory_limit_bytes * 100.0
      else
        0.0
      end

    %{
      limit_bytes: state.memory_limit_bytes,
      usage_bytes: current_usage,
      usage_percentage: usage_percentage,
      facts_count: facts_count,
      agenda_size: agenda_size
    }
  end

  # Private helper functions for memory management

  defp estimate_refraction_memory(refraction_store) do
    # Estimate based on MapSet size and average entry size
    entry_count = MapSet.size(refraction_store)
    # Estimate ~50 bytes per refraction signature entry
    entry_count * 50
  end

  defp estimate_eviction_count(excess_bytes, state) do
    facts_count = map_size(state.working_memory.facts)

    if facts_count > 0 and state.memory_usage_bytes > 0 do
      # Estimate average fact size and suggest eviction count
      avg_fact_size = state.memory_usage_bytes / facts_count
      suggested_count = max(1, round(excess_bytes / avg_fact_size))
      # Cap at 50% of facts to avoid complete eviction
      min(suggested_count, div(facts_count, 2))
    else
      # Default to evicting 10% of facts if we can't estimate
      max(1, div(facts_count, 10))
    end
  end
end
