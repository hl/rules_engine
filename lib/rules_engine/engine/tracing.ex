defmodule RulesEngine.Engine.Tracing do
  @moduledoc """
  Tracing system for RETE network events and debugging.

  Provides structured event logging for fact propagation,
  node activations, rule firings, and performance analysis.
  Supports pluggable subscribers and filtering.
  """

  defstruct [
    # Whether tracing is active
    :enabled,
    # List of trace events
    :events,
    # List of event subscriber PIDs
    :subscribers,
    # Event filter function
    :filter,
    # Maximum events to retain
    :max_events,
    :started_at
  ]

  @type event_type ::
          :assert
          | :retract
          | :modify
          | :alpha_match
          | :beta_join
          | :activation
          | :fire
          | :derive
          | :error

  @type trace_event :: %{
          type: event_type(),
          timestamp: DateTime.t(),
          node_id: term(),
          data: map(),
          correlation_id: term()
        }

  @type t :: %__MODULE__{
          enabled: boolean(),
          events: [trace_event()],
          subscribers: [pid()],
          filter: (trace_event() -> boolean()) | nil,
          max_events: pos_integer(),
          started_at: DateTime.t()
        }

  @doc """
  Create new tracing system.
  """
  @spec new(opts :: keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      enabled: Keyword.get(opts, :enabled, true),
      events: [],
      subscribers: [],
      filter: Keyword.get(opts, :filter),
      max_events: Keyword.get(opts, :max_events, 1000),
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Enable tracing.
  """
  @spec enable(t()) :: t()
  def enable(%__MODULE__{} = tracer) do
    %{tracer | enabled: true}
  end

  @doc """
  Disable tracing.
  """
  @spec disable(t()) :: t()
  def disable(%__MODULE__{} = tracer) do
    %{tracer | enabled: false}
  end

  @doc """
  Add event subscriber.
  """
  @spec subscribe(t(), pid()) :: t()
  def subscribe(%__MODULE__{} = tracer, subscriber_pid) when is_pid(subscriber_pid) do
    if subscriber_pid in tracer.subscribers do
      tracer
    else
      %{tracer | subscribers: [subscriber_pid | tracer.subscribers]}
    end
  end

  @doc """
  Remove event subscriber.
  """
  @spec unsubscribe(t(), pid()) :: t()
  def unsubscribe(%__MODULE__{} = tracer, subscriber_pid) when is_pid(subscriber_pid) do
    %{tracer | subscribers: List.delete(tracer.subscribers, subscriber_pid)}
  end

  @doc """
  Trace an event if tracing is enabled.
  """
  @spec trace(t(), event_type(), node_id :: term(), data :: map(), correlation_id :: term()) ::
          t()
  def trace(%__MODULE__{enabled: false} = tracer, _type, _node_id, _data, _correlation_id) do
    tracer
  end

  def trace(%__MODULE__{enabled: true} = tracer, type, node_id, data, correlation_id) do
    event = %{
      type: type,
      timestamp: DateTime.utc_now(),
      node_id: node_id,
      data: data,
      correlation_id: correlation_id
    }

    if should_trace_event?(tracer, event) do
      new_tracer = add_event(tracer, event)
      notify_subscribers(new_tracer, event)
      new_tracer
    else
      tracer
    end
  end

  @doc """
  Get all trace events.
  """
  @spec events(t()) :: [trace_event()]
  def events(%__MODULE__{} = tracer) do
    Enum.reverse(tracer.events)
  end

  @doc """
  Get events by type.
  """
  @spec events_by_type(t(), event_type()) :: [trace_event()]
  def events_by_type(%__MODULE__{} = tracer, type) do
    tracer.events
    |> Enum.filter(&(&1.type == type))
    |> Enum.reverse()
  end

  @doc """
  Get events by correlation ID.
  """
  @spec events_by_correlation(t(), term()) :: [trace_event()]
  def events_by_correlation(%__MODULE__{} = tracer, correlation_id) do
    tracer.events
    |> Enum.filter(&(&1.correlation_id == correlation_id))
    |> Enum.reverse()
  end

  @doc """
  Clear all trace events.
  """
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = tracer) do
    %{tracer | events: []}
  end

  @doc """
  Get tracing statistics.
  """
  @spec stats(t()) :: map()
  def stats(%__MODULE__{} = tracer) do
    event_counts =
      tracer.events
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, events} -> {type, length(events)} end)
      |> Enum.into(%{})

    %{
      enabled: tracer.enabled,
      total_events: length(tracer.events),
      event_counts: event_counts,
      subscribers: length(tracer.subscribers),
      max_events: tracer.max_events,
      started_at: tracer.started_at
    }
  end

  # Convenience functions for common trace events

  @doc "Trace fact assertion."
  @spec trace_assert(t(), fact_id :: term(), fact :: map(), correlation_id :: term()) :: t()
  def trace_assert(tracer, fact_id, fact, correlation_id \\ nil) do
    trace(tracer, :assert, :working_memory, %{fact_id: fact_id, fact: fact}, correlation_id)
  end

  @doc "Trace fact retraction."
  @spec trace_retract(t(), fact_id :: term(), correlation_id :: term()) :: t()
  def trace_retract(tracer, fact_id, correlation_id \\ nil) do
    trace(tracer, :retract, :working_memory, %{fact_id: fact_id}, correlation_id)
  end

  @doc "Trace alpha memory match."
  @spec trace_alpha_match(t(), node_id :: term(), fact_id :: term(), correlation_id :: term()) ::
          t()
  def trace_alpha_match(tracer, node_id, fact_id, correlation_id \\ nil) do
    trace(tracer, :alpha_match, node_id, %{fact_id: fact_id}, correlation_id)
  end

  @doc "Trace beta join."
  @spec trace_beta_join(
          t(),
          node_id :: term(),
          token :: map(),
          fact_id :: term(),
          correlation_id :: term()
        ) :: t()
  def trace_beta_join(tracer, node_id, token, fact_id, correlation_id \\ nil) do
    trace(tracer, :beta_join, node_id, %{token: token, fact_id: fact_id}, correlation_id)
  end

  @doc "Trace rule activation."
  @spec trace_activation(t(), production_id :: term(), token :: map(), correlation_id :: term()) ::
          t()
  def trace_activation(tracer, production_id, token, correlation_id \\ nil) do
    trace(tracer, :activation, production_id, %{token: token}, correlation_id)
  end

  @doc "Trace rule firing."
  @spec trace_fire(t(), production_id :: term(), token :: map(), correlation_id :: term()) :: t()
  def trace_fire(tracer, production_id, token, correlation_id \\ nil) do
    trace(tracer, :fire, production_id, %{token: token}, correlation_id)
  end

  # Private Implementation

  defp should_trace_event?(tracer, event) do
    case tracer.filter do
      nil -> true
      filter_fn when is_function(filter_fn, 1) -> filter_fn.(event)
      _ -> true
    end
  end

  defp add_event(tracer, event) do
    new_events = [event | tracer.events]

    # Trim events if over limit
    trimmed_events =
      if length(new_events) > tracer.max_events do
        Enum.take(new_events, tracer.max_events)
      else
        new_events
      end

    %{tracer | events: trimmed_events}
  end

  defp notify_subscribers(tracer, event) do
    tracer.subscribers
    |> Enum.each(fn subscriber ->
      send(subscriber, {:trace_event, event})
    end)
  end
end
