defmodule RulesEngine.Engine.MemoryManager do
  @moduledoc """
  Memory management for tenant engines.

  Provides memory tracking, limit enforcement, and eviction policies
  to prevent resource exhaustion in multi-tenant environments.
  """

  alias RulesEngine.Engine.{State, WorkingMemory}
  require Logger

  @doc """
  Check memory limits and apply eviction if necessary.
  Returns {:ok, new_state} or {:error, reason}.
  """
  @spec check_and_enforce_limits(State.t(), non_neg_integer()) ::
          {:ok, State.t()} | {:error, :memory_limit_exceeded}
  def check_and_enforce_limits(%State{} = state, operation_count) do
    # Only check memory periodically or if no limit is set
    if State.should_check_memory?(state, operation_count) do
      case State.update_memory_usage(state) do
        {:ok, updated_state} ->
          # Memory usage is within limits
          {:ok, updated_state}

        {:error, :memory_limit_exceeded, suggested_eviction_count} ->
          # Attempt eviction to bring memory usage under limit
          case attempt_eviction(state, suggested_eviction_count) do
            {:ok, evicted_state} ->
              # Re-check memory after eviction
              case State.update_memory_usage(evicted_state) do
                {:ok, final_state} ->
                  log_memory_eviction(state, suggested_eviction_count, :success)
                  {:ok, final_state}

                {:error, :memory_limit_exceeded, _} ->
                  # Still over limit after eviction
                  log_memory_eviction(state, suggested_eviction_count, :insufficient)
                  {:error, :memory_limit_exceeded}
              end

            {:error, reason} ->
              log_memory_eviction(state, suggested_eviction_count, :failed)
              {:error, reason}
          end
      end
    else
      # Skip memory check for this operation
      {:ok, state}
    end
  end

  @doc """
  Attempt to evict facts to free memory using the configured eviction policy.
  """
  @spec attempt_eviction(State.t(), non_neg_integer()) ::
          {:ok, State.t()} | {:error, :eviction_failed}
  def attempt_eviction(%State{} = state, eviction_count) when eviction_count > 0 do
    facts_to_evict = select_facts_for_eviction(state, eviction_count)

    if length(facts_to_evict) > 0 do
      # Remove selected facts from working memory
      fact_ids = Enum.map(facts_to_evict, fn {id, _fact} -> id end)
      {new_state, _outputs} = WorkingMemory.retract_facts(state, fact_ids)

      # Emit telemetry for eviction event
      :telemetry.execute([:rules_engine, :memory, :eviction], %{
        tenant_key: state.tenant_key,
        evicted_count: length(fact_ids),
        requested_count: eviction_count
      })

      {:ok, new_state}
    else
      {:error, :no_facts_to_evict}
    end
  end

  def attempt_eviction(%State{} = state, _eviction_count) do
    # No eviction needed
    {:ok, state}
  end

  @doc """
  Get current memory usage statistics for monitoring.
  """
  @spec get_memory_stats(State.t()) :: map()
  def get_memory_stats(%State{} = state) do
    State.memory_stats(state)
  end

  # Private helper functions

  defp select_facts_for_eviction(%State{} = state, eviction_count) do
    facts = state.working_memory.facts

    case state.memory_eviction_policy do
      :lru ->
        # Evict least recently used facts (approximation using insertion order)
        facts
        |> Enum.take(eviction_count)

      :oldest ->
        # Evict oldest facts by ID (assumes chronological ID ordering)
        facts
        |> Enum.sort_by(fn {id, _fact} -> id end)
        |> Enum.take(eviction_count)

      :random ->
        # Evict random facts
        facts
        |> Enum.take_random(eviction_count)

      _ ->
        # Default to LRU behavior
        facts
        |> Enum.take(eviction_count)
    end
  end

  defp log_memory_eviction(state, eviction_count, result) do
    memory_stats = State.memory_stats(state)

    Logger.warning([
      "Memory eviction attempt: ",
      "tenant=#{inspect(state.tenant_key)} ",
      "result=#{result} ",
      "requested=#{eviction_count} ",
      "usage=#{memory_stats.usage_percentage}% ",
      "facts=#{memory_stats.facts_count}"
    ])
  end
end
