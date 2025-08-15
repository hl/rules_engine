defmodule RulesEngine.Engine.ActionExecutor do
  @moduledoc """
  Executes rule RHS actions and handles derived fact generation.

  Supports various action types:
  - emit: Generate derived facts with lineage
  - call: Invoke callback functions with isolation
  - log: Structured logging with context

  Tracks lineage for debugging and maintains isolation between
  rule execution and external side effects.
  """

  alias RulesEngine.Engine.{Activation, Token}

  @type action :: %{
          type: :emit | :call | :log,
          params: map(),
          metadata: map()
        }

  @type execution_result :: %{
          derived_facts: [map()],
          side_effects: [map()],
          errors: [map()]
        }

  @doc """
  Execute all actions in a production rule's RHS.
  """
  @spec execute_actions(state :: map(), activation :: Activation.t()) ::
          {map(), execution_result()}
  def execute_actions(state, %Activation{} = activation) do
    # Get production node from network
    production_node = get_production_node(state.network, activation.production_id)

    case production_node do
      nil ->
        # No production found - should not happen in valid network
        error = %{
          type: :missing_production,
          production_id: activation.production_id,
          message: "Production node not found in network"
        }

        result = %{derived_facts: [], side_effects: [], errors: [error]}
        {state, result}

      node ->
        actions = Map.get(node, :actions, [])
        execute_action_list(state, actions, activation)
    end
  end

  @doc """
  Execute a list of actions in sequence.
  """
  @spec execute_action_list(state :: map(), actions :: [action()], activation :: Activation.t()) ::
          {map(), execution_result()}
  def execute_action_list(state, actions, activation) do
    initial_result = %{derived_facts: [], side_effects: [], errors: []}

    Enum.reduce(actions, {state, initial_result}, fn action, {acc_state, acc_result} ->
      {new_state, action_result} = execute_single_action(acc_state, action, activation)

      merged_result = %{
        derived_facts: acc_result.derived_facts ++ action_result.derived_facts,
        side_effects: acc_result.side_effects ++ action_result.side_effects,
        errors: acc_result.errors ++ action_result.errors
      }

      {new_state, merged_result}
    end)
  end

  @doc """
  Execute a single action.
  """
  @spec execute_single_action(state :: map(), action :: action(), activation :: Activation.t()) ::
          {map(), execution_result()}
  def execute_single_action(state, action, activation) do
    try do
      case action.type do
        :emit ->
          execute_emit_action(state, action, activation)

        :call ->
          execute_call_action(state, action, activation)

        :log ->
          execute_log_action(state, action, activation)

        _ ->
          error = %{
            type: :unknown_action,
            action_type: action.type,
            message: "Unknown action type"
          }

          {state, %{derived_facts: [], side_effects: [], errors: [error]}}
      end
    rescue
      exception ->
        error = %{
          type: :action_exception,
          action_type: action.type,
          exception: Exception.message(exception),
          stacktrace: __STACKTRACE__
        }

        {state, %{derived_facts: [], side_effects: [], errors: [error]}}
    end
  end

  # Private Implementation

  defp get_production_node(network, production_id) do
    RulesEngine.Engine.Network.get_production_node(network, production_id)
  end

  defp execute_emit_action(state, action, activation) do
    # Generate derived facts from action parameters and token bindings
    bindings = Token.bindings(activation.token)

    # Extract fact template from action params
    fact_template = Map.get(action.params, :fact, %{})

    # Substitute bindings into template
    derived_fact = substitute_bindings(fact_template, bindings)

    # Add metadata for lineage tracking
    enriched_fact =
      Map.merge(derived_fact, %{
        id: generate_fact_id(),
        derived_from: %{
          production_id: activation.production_id,
          token_signature: Token.signature(activation.token),
          parent_facts: Token.get_wmes(activation.token),
          derived_at: DateTime.utc_now()
        }
      })

    result = %{
      derived_facts: [enriched_fact],
      side_effects: [],
      errors: []
    }

    {state, result}
  end

  defp execute_call_action(state, action, activation) do
    # Execute callback function with isolation
    callback_module = Map.get(action.params, :module)
    callback_function = Map.get(action.params, :function)
    callback_args = Map.get(action.params, :args, [])

    # Add activation context to args
    context = %{
      activation: activation,
      bindings: Token.bindings(activation.token)
    }

    extended_args = [context | callback_args]

    try do
      # Execute callback in controlled manner
      callback_result = apply(callback_module, callback_function, extended_args)

      side_effect = %{
        type: :callback,
        module: callback_module,
        function: callback_function,
        result: callback_result,
        executed_at: DateTime.utc_now()
      }

      result = %{
        derived_facts: [],
        side_effects: [side_effect],
        errors: []
      }

      {state, result}
    catch
      kind, reason ->
        error = %{
          type: :callback_error,
          kind: kind,
          reason: reason,
          module: callback_module,
          function: callback_function
        }

        result = %{
          derived_facts: [],
          side_effects: [],
          errors: [error]
        }

        {state, result}
    end
  end

  defp execute_log_action(state, action, activation) do
    # Structured logging with context
    level = Map.get(action.params, :level, :info)
    message = Map.get(action.params, :message, "Rule fired")

    # Build log context
    context = %{
      production_id: activation.production_id,
      bindings: Token.bindings(activation.token),
      facts: Token.get_wmes(activation.token),
      tenant: state.tenant_key,
      timestamp: DateTime.utc_now()
    }

    # Log with appropriate level
    case level do
      :debug -> Logger.debug(message, context)
      :info -> Logger.info(message, context)
      :warn -> Logger.warn(message, context)
      :error -> Logger.error(message, context)
      _ -> Logger.info(message, context)
    end

    side_effect = %{
      type: :log,
      level: level,
      message: message,
      context: context
    }

    result = %{
      derived_facts: [],
      side_effects: [side_effect],
      errors: []
    }

    {state, result}
  end

  defp substitute_bindings(template, bindings) when is_map(template) do
    template
    |> Enum.map(fn {key, value} ->
      {key, substitute_bindings(value, bindings)}
    end)
    |> Enum.into(%{})
  end

  defp substitute_bindings({:binding, var_name}, bindings) when is_atom(var_name) do
    # Substitute binding variable
    Map.get(bindings, var_name, {:unbound, var_name})
  end

  defp substitute_bindings(value, _bindings) do
    # Literal value, return as-is
    value
  end

  defp generate_fact_id do
    # Generate unique fact ID
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
