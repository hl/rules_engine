defmodule RulesEngine.Engine do
  @moduledoc """
  Engine GenServer implementing the RETE runtime for a single tenant.

  Manages working memory, propagates facts through the compiled network,
  maintains the agenda, and executes rule actions. Each engine instance
  is isolated per tenant.

  ## Core APIs

  - `start_tenant/3` - Start engine for a tenant with compiled network
  - `stop_tenant/1` - Stop tenant engine
  - `assert/2` - Add facts to working memory
  - `modify/2` - Update existing facts by ID
  - `retract/2` - Remove facts from working memory
  - `run/2` - Execute agenda until completion or limit
  - `step/1` - Execute single agenda step
  - `reset/1` - Clear working memory and agenda

  ## Working Memory Structures

  The engine maintains several key data structures:

  - **Working Memory**: All active facts indexed by ID and type
  - **Alpha Memories**: Facts matching specific patterns
  - **Beta Memories**: Partial matches (tokens) from joins
  - **Agenda**: Conflict set of activations ready to fire
  - **Token Tables**: Join results and propagation state

  ## Batch Processing

  Operations are processed atomically in batches to maintain consistency.
  The agenda only fires after all operations in a batch complete.
  """

  use GenServer
  require Logger

  alias RulesEngine.Engine.{State, WorkingMemory, Agenda, Network, Tracing}

  # Client API

  @doc """
  Start an engine for the given tenant with a compiled network.

  Options:
  - `:trace` - Enable tracing (default: false)
  - `:partition_count` - Number of internal partitions (default: 1)
  - `:fire_limit` - Max activations per run (default: 1000)
  - `:agenda_policy` - Module implementing agenda ordering
  """
  @spec start_tenant(tenant_key :: term(), network :: map(), opts :: keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start_tenant(tenant_key, network, opts \\ []) do
    GenServer.start_link(__MODULE__, {tenant_key, network, opts}, name: via_tuple(tenant_key))
  end

  @doc "Stop the engine for the given tenant."
  @spec stop_tenant(tenant_key :: term()) :: :ok
  def stop_tenant(tenant_key) do
    case GenServer.whereis(via_tuple(tenant_key)) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  @doc "Find the PID for a tenant engine."
  @spec whereis(tenant_key :: term()) :: pid() | nil
  def whereis(tenant_key) do
    GenServer.whereis(via_tuple(tenant_key))
  end

  @doc """
  Assert facts into working memory.

  Facts must have `:id` and `:type` fields. Returns immediate or batched
  depending on options.
  """
  @spec assert(pid() | term(), facts :: map() | [map()], opts :: keyword()) ::
          :ok | {:ok, map()}
  def assert(engine, facts, opts \\ [])

  def assert(engine, facts, opts) when is_pid(engine) do
    GenServer.call(engine, {:assert, List.wrap(facts), opts})
  end

  def assert(tenant_key, facts, opts) when not is_pid(tenant_key) do
    case whereis(tenant_key) do
      nil -> {:error, :tenant_not_found}
      pid -> assert(pid, facts, opts)
    end
  end

  @doc """
  Modify existing facts by ID.

  Performs retract of old version then assert of new version atomically.
  """
  @spec modify(pid() | term(), facts :: map() | [map()], opts :: keyword()) ::
          :ok | {:ok, map()}
  def modify(engine, facts, opts \\ [])

  def modify(engine, facts, opts) when is_pid(engine) do
    GenServer.call(engine, {:modify, List.wrap(facts), opts})
  end

  def modify(tenant_key, facts, opts) when not is_pid(tenant_key) do
    case whereis(tenant_key) do
      nil -> {:error, :tenant_not_found}
      pid -> modify(pid, facts, opts)
    end
  end

  @doc """
  Retract facts by ID.

  Removes facts from working memory and propagates retractions through network.
  """
  @spec retract(pid() | term(), ids :: term() | [term()], opts :: keyword()) ::
          :ok | {:ok, map()}
  def retract(engine, ids, opts \\ [])

  def retract(engine, ids, opts) when is_pid(engine) do
    GenServer.call(engine, {:retract, List.wrap(ids), opts})
  end

  def retract(tenant_key, ids, opts) when not is_pid(tenant_key) do
    case whereis(tenant_key) do
      nil -> {:error, :tenant_not_found}
      pid -> retract(pid, ids, opts)
    end
  end

  @doc """
  Run the agenda until completion or fire limit reached.

  Executes all ready activations in agenda order up to the fire limit.
  """
  @spec run(pid() | term(), opts :: keyword()) :: {:ok, map()}
  def run(engine, opts \\ [])

  def run(engine, opts) when is_pid(engine) do
    GenServer.call(engine, {:run, opts}, :infinity)
  end

  def run(tenant_key, opts) when not is_pid(tenant_key) do
    case whereis(tenant_key) do
      nil -> {:error, :tenant_not_found}
      pid -> run(pid, opts)
    end
  end

  @doc """
  Execute a single activation from the agenda.

  Returns the activation details and any derived facts.
  """
  @spec step(pid() | term()) :: {:ok, map()} | {:error, :agenda_empty}
  def step(engine) when is_pid(engine) do
    GenServer.call(engine, :step)
  end

  def step(tenant_key) when not is_pid(tenant_key) do
    case whereis(tenant_key) do
      nil -> {:error, :tenant_not_found}
      pid -> step(pid)
    end
  end

  @doc """
  Reset working memory and agenda to initial state.

  Preserves the compiled network but clears all facts and activations.
  """
  @spec reset(pid() | term()) :: :ok
  def reset(engine) when is_pid(engine) do
    GenServer.call(engine, :reset)
  end

  def reset(tenant_key) when not is_pid(tenant_key) do
    case whereis(tenant_key) do
      nil -> {:error, :tenant_not_found}
      pid -> reset(pid)
    end
  end

  @doc """
  Take a snapshot of engine state for persistence.

  Returns all data needed to restore the engine to current state.
  """
  @spec snapshot(pid() | term()) :: {:ok, map()}
  def snapshot(engine) when is_pid(engine) do
    GenServer.call(engine, :snapshot)
  end

  def snapshot(tenant_key) when not is_pid(tenant_key) do
    case whereis(tenant_key) do
      nil -> {:error, :tenant_not_found}
      pid -> snapshot(pid)
    end
  end

  # GenServer Callbacks

  @impl true
  def init({tenant_key, network, opts}) do
    Logger.debug("Starting engine for tenant #{inspect(tenant_key)}")

    state = State.new(tenant_key, network, opts)

    {:ok, state}
  end

  @impl true
  def handle_call({:assert, facts, opts}, _from, state) do
    with {:ok, new_state, outputs} <- do_assert(state, facts, opts) do
      maybe_run_agenda(new_state, outputs, opts)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:modify, facts, opts}, _from, state) do
    with {:ok, new_state, outputs} <- do_modify(state, facts, opts) do
      maybe_run_agenda(new_state, outputs, opts)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:retract, ids, opts}, _from, state) do
    with {:ok, new_state, outputs} <- do_retract(state, ids, opts) do
      maybe_run_agenda(new_state, outputs, opts)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:run, opts}, _from, state) do
    fire_limit = Keyword.get(opts, :fire_limit, state.fire_limit)
    {new_state, outputs} = run_agenda(state, fire_limit)

    result = format_outputs(outputs, opts)
    {:reply, {:ok, result}, new_state}
  end

  @impl true
  def handle_call(:step, _from, state) do
    case Agenda.next_activation(state.agenda) do
      nil ->
        {:reply, {:error, :agenda_empty}, state}

      activation ->
        {new_state, outputs} = fire_activation(state, activation)
        result = format_outputs(outputs, [])
        {:reply, {:ok, result}, new_state}
    end
  end

  @impl true
  def handle_call(:reset, _from, state) do
    new_state = State.reset(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    snapshot = State.snapshot(state)
    {:reply, {:ok, snapshot}, state}
  end

  # Private Implementation

  defp via_tuple(tenant_key) do
    {:via, Registry, {RulesEngine.Registry, {:tenant, tenant_key}}}
  end

  defp do_assert(state, facts, _opts) do
    # Validate facts have required fields
    case validate_facts(facts) do
      :ok ->
        # Add facts to working memory and propagate
        {new_state, derived_facts} = WorkingMemory.assert_facts(state, facts)

        outputs = %{
          asserted: facts,
          derived: derived_facts,
          activations: Agenda.recent_activations(new_state.agenda)
        }

        {:ok, new_state, outputs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_modify(state, facts, _opts) do
    case validate_facts(facts) do
      :ok ->
        # Extract IDs and perform retract + assert
        ids = Enum.map(facts, & &1.id)

        with {:ok, retract_state, _retract_outputs} <- do_retract(state, ids, []),
             {:ok, new_state, assert_outputs} <- do_assert(retract_state, facts, []) do
          outputs = %{
            modified: facts,
            derived: assert_outputs.derived,
            activations: Agenda.recent_activations(new_state.agenda)
          }

          {:ok, new_state, outputs}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_retract(state, ids, _opts) do
    # Remove facts from working memory and propagate
    {new_state, retracted_facts} = WorkingMemory.retract_facts(state, ids)

    outputs = %{
      retracted: retracted_facts,
      derived: [],
      activations: []
    }

    {:ok, new_state, outputs}
  end

  defp validate_facts(facts) do
    Enum.reduce_while(facts, :ok, fn fact, :ok ->
      cond do
        not is_map(fact) ->
          {:halt, {:error, {:invalid_fact, "Facts must be maps", fact}}}

        not Map.has_key?(fact, :id) ->
          {:halt, {:error, {:invalid_fact, "Facts must have :id field", fact}}}

        not Map.has_key?(fact, :type) ->
          {:halt, {:error, {:invalid_fact, "Facts must have :type field", fact}}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp maybe_run_agenda(state, outputs, opts) do
    if Keyword.get(opts, :batch, true) do
      # Don't run agenda immediately, just return outputs
      result = format_outputs(outputs, opts)
      {:reply, format_result(result, opts), state}
    else
      # Run agenda and merge outputs
      fire_limit = Keyword.get(opts, :fire_limit, state.fire_limit)
      {new_state, agenda_outputs} = run_agenda(state, fire_limit)

      merged_outputs = merge_outputs(outputs, agenda_outputs)
      result = format_outputs(merged_outputs, opts)
      {:reply, format_result(result, opts), new_state}
    end
  end

  defp run_agenda(state, fire_limit) do
    run_agenda(state, fire_limit, [])
  end

  defp run_agenda(state, 0, outputs) do
    {state, Enum.reverse(outputs)}
  end

  defp run_agenda(state, fire_limit, outputs) do
    case Agenda.next_activation(state.agenda) do
      nil ->
        {state, Enum.reverse(outputs)}

      activation ->
        {new_state, step_outputs} = fire_activation(state, activation)
        run_agenda(new_state, fire_limit - 1, [step_outputs | outputs])
    end
  end

  defp fire_activation(state, activation) do
    # Check refraction - don't fire if already fired with same token signature
    refraction_key = Activation.refraction_key(activation)

    # Trace activation lifecycle
    new_tracer =
      if state.tracing_enabled do
        Tracing.trace_fire(state.tracer, activation.production_id, activation.token)
      else
        state.tracer
      end

    if MapSet.member?(state.refraction_store, refraction_key) do
      # Already fired, just remove from agenda
      new_agenda = Agenda.remove_activation(state.agenda, activation)
      new_state = %{state | agenda: new_agenda, tracer: new_tracer}

      outputs = %{
        fired: nil,
        derived: [],
        trace: if(state.tracing_enabled, do: [trace_refraction_event(activation)], else: []),
        refracted: activation
      }

      {new_state, outputs}
    else
      # Fire the activation and add to refraction store
      {intermediate_state, outputs} =
        execute_rule_actions(
          %{state | tracer: new_tracer},
          activation
        )

      # Trace derived facts if any
      final_tracer =
        if state.tracing_enabled and length(outputs.derived) > 0 do
          Enum.reduce(outputs.derived, intermediate_state.tracer, fn derived_fact, tracer_acc ->
            Tracing.trace(
              tracer_acc,
              :derive,
              activation.production_id,
              %{derived_fact: derived_fact},
              nil
            )
          end)
        else
          intermediate_state.tracer
        end

      # Add to refraction store and remove from agenda
      new_refraction_store = MapSet.put(intermediate_state.refraction_store, refraction_key)
      final_agenda = Agenda.remove_activation(intermediate_state.agenda, activation)

      final_state = %{
        intermediate_state
        | agenda: final_agenda,
          refraction_store: new_refraction_store,
          tracer: final_tracer
      }

      final_outputs =
        Map.merge(outputs, %{
          fired: activation,
          trace: build_trace_events(state, activation, outputs)
        })

      {final_state, final_outputs}
    end
  end

  defp execute_rule_actions(state, activation) do
    # Execute actual rule RHS actions using ActionExecutor
    alias RulesEngine.Engine.ActionExecutor

    {new_state, execution_result} = ActionExecutor.execute_actions(state, activation)

    # Assert any derived facts back into working memory
    final_state =
      if length(execution_result.derived_facts) > 0 do
        {updated_state, _} = WorkingMemory.assert_facts(new_state, execution_result.derived_facts)
        updated_state
      else
        new_state
      end

    outputs = %{
      derived: execution_result.derived_facts,
      side_effects: execution_result.side_effects,
      errors: execution_result.errors
    }

    {final_state, outputs}
  end

  defp merge_outputs(outputs1, outputs2) when is_list(outputs2) do
    Enum.reduce(outputs2, outputs1, &merge_outputs(&2, &1))
  end

  defp merge_outputs(outputs1, outputs2) do
    %{
      asserted: Map.get(outputs1, :asserted, []) ++ Map.get(outputs2, :asserted, []),
      modified: Map.get(outputs1, :modified, []) ++ Map.get(outputs2, :modified, []),
      retracted: Map.get(outputs1, :retracted, []) ++ Map.get(outputs2, :retracted, []),
      derived: Map.get(outputs1, :derived, []) ++ Map.get(outputs2, :derived, []),
      activations: Map.get(outputs1, :activations, []) ++ Map.get(outputs2, :activations, []),
      fired: Map.get(outputs2, :fired, Map.get(outputs1, :fired)),
      refracted: Map.get(outputs2, :refracted, Map.get(outputs1, :refracted)),
      trace: Map.get(outputs1, :trace, []) ++ Map.get(outputs2, :trace, [])
    }
  end

  defp format_outputs(outputs, opts) do
    return_mode = Keyword.get(opts, :return, :all)

    case return_mode do
      :none -> %{}
      :activations -> Map.take(outputs, [:activations])
      :derived -> Map.take(outputs, [:derived])
      :all -> outputs
    end
  end

  defp format_result(result, opts) do
    case Keyword.get(opts, :return, :all) do
      :none -> :ok
      _ -> {:ok, result}
    end
  end

  # Tracing helper functions

  defp trace_refraction_event(activation) do
    %{
      type: :refraction,
      timestamp: DateTime.utc_now(),
      production_id: activation.production_id,
      token_signature: Activation.token_signature(activation),
      message: "Activation refracted - already fired with same token"
    }
  end

  defp build_trace_events(state, activation, outputs) do
    if state.tracing_enabled do
      base_events = [
        %{
          type: :rule_fire,
          timestamp: DateTime.utc_now(),
          production_id: activation.production_id,
          bindings: Activation.bindings(activation),
          facts: Activation.wmes(activation)
        }
      ]

      derived_events =
        Enum.map(outputs.derived, fn derived_fact ->
          %{
            type: :fact_derived,
            timestamp: DateTime.utc_now(),
            derived_fact: derived_fact,
            lineage: Map.get(derived_fact, :derived_from)
          }
        end)

      base_events ++ derived_events
    else
      []
    end
  end
end
