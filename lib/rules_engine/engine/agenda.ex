defmodule RulesEngine.Engine.Agenda do
  @moduledoc """
  Agenda manages the conflict set of rule activations.

  The agenda maintains a priority queue of activations ready to fire,
  ordered by configurable policies (salience, recency, specificity).
  Supports agenda policies and refraction control.
  """

  alias RulesEngine.Engine.Activation

  defstruct [
    # Priority queue of activations
    :activations,
    # Agenda ordering policy module
    :policy,
    # Recently added activations for tracking
    :recent,
    # Total activations fired
    :fired_count,
    :created_at
  ]

  @type t :: %__MODULE__{
          activations: :queue.queue(Activation.t()),
          policy: module(),
          recent: [Activation.t()],
          fired_count: non_neg_integer(),
          created_at: DateTime.t()
        }

  @doc """
  Create new agenda with optional policy module.
  """
  @spec new(opts :: keyword()) :: t()
  def new(opts \\ []) do
    policy = Keyword.get(opts, :agenda_policy, RulesEngine.Engine.DefaultAgendaPolicy)

    %__MODULE__{
      activations: :queue.new(),
      policy: policy,
      recent: [],
      fired_count: 0,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Add an activation to the agenda.
  """
  @spec add_activation(t(), Activation.t()) :: t()
  def add_activation(%__MODULE__{} = agenda, %Activation{} = activation) do
    # Insert activation in priority order according to policy
    new_queue = insert_by_priority(agenda.activations, activation, agenda.policy)
    new_recent = [activation | agenda.recent]

    %{agenda | activations: new_queue, recent: new_recent}
  end

  @doc """
  Remove a specific activation from the agenda.
  """
  @spec remove_activation(t(), Activation.t()) :: t()
  def remove_activation(%__MODULE__{} = agenda, %Activation{} = activation) do
    new_queue = remove_from_queue(agenda.activations, activation)

    %{agenda | activations: new_queue}
  end

  @doc """
  Get the next activation to fire (highest priority).
  """
  @spec next_activation(t()) :: Activation.t() | nil
  def next_activation(%__MODULE__{} = agenda) do
    case :queue.out(agenda.activations) do
      {{:value, activation}, _new_queue} ->
        # Return activation without updating state (caller handles state update)
        # Note: This function is read-only - state updates handled by pop_activation/1
        activation

      {:empty, _queue} ->
        nil
    end
  end

  @doc """
  Remove and return the next activation, updating the agenda.
  """
  @spec pop_activation(t()) :: {Activation.t() | nil, t()}
  def pop_activation(%__MODULE__{} = agenda) do
    case :queue.out(agenda.activations) do
      {{:value, activation}, new_queue} ->
        new_agenda = %{agenda | activations: new_queue, fired_count: agenda.fired_count + 1}
        {activation, new_agenda}

      {:empty, _queue} ->
        {nil, agenda}
    end
  end

  @doc """
  Get recently added activations for tracking.
  """
  @spec recent_activations(t()) :: [Activation.t()]
  def recent_activations(%__MODULE__{} = agenda) do
    agenda.recent
  end

  @doc """
  Clear recent activations list.
  """
  @spec clear_recent(t()) :: t()
  def clear_recent(%__MODULE__{} = agenda) do
    %{agenda | recent: []}
  end

  @doc """
  Check if agenda is empty.
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = agenda) do
    :queue.is_empty(agenda.activations)
  end

  @doc """
  Get size of agenda.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = agenda) do
    :queue.len(agenda.activations)
  end

  @doc """
  Get all activations in priority order.
  """
  @spec all_activations(t()) :: [Activation.t()]
  def all_activations(%__MODULE__{} = agenda) do
    :queue.to_list(agenda.activations)
  end

  @doc """
  Create snapshot of agenda state.
  """
  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = agenda) do
    %{
      size: size(agenda),
      fired_count: agenda.fired_count,
      policy: agenda.policy,
      activations: all_activations(agenda),
      created_at: agenda.created_at
    }
  end

  # Private Implementation

  defp insert_by_priority(queue, activation, policy) do
    # Use proper priority queue implementation with binary insertion
    case :queue.is_empty(queue) do
      true ->
        :queue.in(activation, queue)

      false ->
        insert_activation_in_order(queue, activation, policy, :queue.new())
    end
  end

  defp insert_activation_in_order(queue, activation, policy, acc) do
    case :queue.out(queue) do
      {:empty, _} ->
        :queue.in(activation, acc)

      {{:value, current}, remaining} ->
        case policy.compare(activation, current) do
          true ->
            # Activation has higher priority, insert here
            :queue.join(acc, :queue.from_list([activation | :queue.to_list(queue)]))

          false ->
            # Continue searching for insertion point
            insert_activation_in_order(remaining, activation, policy, :queue.in(current, acc))
        end
    end
  end

  defp remove_from_queue(queue, activation) do
    activations = :queue.to_list(queue)
    filtered_activations = Enum.reject(activations, &(&1 == activation))

    :queue.from_list(filtered_activations)
  end
end
