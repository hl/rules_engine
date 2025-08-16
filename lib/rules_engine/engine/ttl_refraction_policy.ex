defmodule RulesEngine.Engine.TtlRefractionPolicy do
  @moduledoc """
  Time-based refraction policy with configurable TTL.

  Similar to default refraction but entries expire after a
  configurable time-to-live period. Useful for high-churn scenarios
  where old refraction entries should eventually allow re-firing.
  """

  @behaviour RulesEngine.Engine.RefractionPolicy

  alias RulesEngine.Engine.Activation

  @doc """
  Generate refraction key with timestamp.
  """
  @impl true
  def refraction_key(%Activation{} = activation) do
    Activation.refraction_key(activation)
  end

  @doc """
  Check refraction with TTL expiry logic.
  """
  @impl true
  def should_refract(%Activation{} = activation, store, opts) do
    key = refraction_key(activation)
    # Default 1 hour
    ttl_seconds = Keyword.get(opts, :ttl_seconds, 3600)
    now = DateTime.utc_now()

    case Map.get(store, key) do
      nil ->
        # Not seen before, allow and store with timestamp
        new_store = Map.put(store, key, now)
        {:fire, new_store}

      timestamp ->
        # Check if expired
        age_seconds = DateTime.diff(now, timestamp, :second)

        if age_seconds >= ttl_seconds do
          # Expired, allow and update timestamp
          new_store = Map.put(store, key, now)
          {:fire, new_store}
        else
          # Still valid, refract
          {:refract, store}
        end
    end
  end

  @doc """
  Create initial Map store for TTL tracking.
  """
  @impl true
  def init_store(_opts) do
    %{}
  end

  @doc """
  Clean expired entries from the store.
  """
  @impl true
  def cleanup_store(store, opts) do
    ttl_seconds = Keyword.get(opts, :ttl_seconds, 3600)
    cutoff = DateTime.add(DateTime.utc_now(), -ttl_seconds, :second)

    Enum.reduce(store, %{}, fn {key, timestamp}, acc ->
      if DateTime.compare(timestamp, cutoff) == :gt do
        Map.put(acc, key, timestamp)
      else
        acc
      end
    end)
  end

  @doc """
  Get policy name for debugging.
  """
  @impl true
  def name, do: "ttl"

  @doc """
  Get policy description.
  """
  @impl true
  def description do
    "Time-based refraction with configurable TTL expiry"
  end
end
