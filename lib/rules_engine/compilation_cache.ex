defmodule RulesEngine.CompilationCache do
  @moduledoc """
  ETS-based compilation result caching to improve performance.

  Caches compiled IR results keyed by source checksum to avoid
  recompilation of identical rule sets. Includes cache statistics
  and eviction policies for memory management.
  """

  use GenServer
  require Logger

  @table_name :rules_engine_compilation_cache
  @cache_stats :rules_engine_cache_stats

  defmodule CacheEntry do
    @moduledoc false
    defstruct [
      :checksum,
      :tenant_id,
      :ir,
      :compiled_at,
      :expires_at,
      :access_count,
      :last_accessed
    ]
  end

  defmodule Stats do
    @moduledoc false
    defstruct [
      :hits,
      :misses,
      :evictions,
      :total_entries,
      :memory_usage
    ]

    def new do
      %__MODULE__{
        hits: 0,
        misses: 0,
        evictions: 0,
        total_entries: 0,
        memory_usage: 0
      }
    end
  end

  # Client API

  @doc """
  Start the compilation cache.

  Options:
  - `:max_entries` - Maximum number of cached entries (default: 1000)
  - `:max_memory_mb` - Maximum memory usage in MB (default: 100)
  - `:ttl_seconds` - Time-to-live for cache entries in seconds (default: 3600, 0 = no TTL)
  - `:eviction_policy` - `:lru`, `:lfu`, or `:ttl` (default: :lru)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get cached IR for the given checksum and tenant.

  Returns `{:hit, ir}` if found in cache, `{:miss}` if not found.
  """
  def get(checksum, tenant_id) do
    case :ets.lookup(@table_name, {checksum, tenant_id}) do
      [{_key, entry}] ->
        now = DateTime.utc_now()

        # Check if entry has expired
        if entry.expires_at && DateTime.compare(now, entry.expires_at) == :gt do
          # Entry has expired, remove it and return miss
          :ets.delete(@table_name, {checksum, tenant_id})
          GenServer.cast(__MODULE__, :cache_miss)
          :miss
        else
          # Update access statistics
          updated_entry = %{
            entry
            | access_count: entry.access_count + 1,
              last_accessed: now
          }

          :ets.insert(@table_name, {{checksum, tenant_id}, updated_entry})

          GenServer.cast(__MODULE__, :cache_hit)
          {:hit, entry.ir}
        end

      [] ->
        GenServer.cast(__MODULE__, :cache_miss)
        :miss
    end
  end

  @doc """
  Put IR in cache for the given checksum and tenant.
  """
  def put(checksum, tenant_id, ir) do
    GenServer.call(__MODULE__, {:cache_put, checksum, tenant_id, ir})
  end

  @doc """
  Clear all cached entries for a tenant.
  """
  def clear_tenant(tenant_id) do
    GenServer.call(__MODULE__, {:clear_tenant, tenant_id})
  end

  @doc """
  Clear all cached entries.
  """
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  @doc """
  Get cache statistics.
  """
  def stats do
    case :ets.lookup(@cache_stats, :stats) do
      [{:stats, stats}] -> stats
      [] -> Stats.new()
    end
  end

  @doc """
  Get cache information including entries and memory usage.
  """
  def info do
    stats = stats()
    entries = :ets.tab2list(@table_name)

    %{
      stats: stats,
      entry_count: length(entries),
      memory_words: :ets.info(@table_name, :memory),
      memory_bytes: :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)
    }
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    max_entries = Keyword.get(opts, :max_entries, 1000)
    max_memory_mb = Keyword.get(opts, :max_memory_mb, 100)
    ttl_seconds = Keyword.get(opts, :ttl_seconds, 3600)
    eviction_policy = Keyword.get(opts, :eviction_policy, :lru)

    # Create ETS tables
    :ets.new(@table_name, [:named_table, :public, {:read_concurrency, true}])
    :ets.new(@cache_stats, [:named_table, :public])

    # Initialize stats
    :ets.insert(@cache_stats, {:stats, Stats.new()})

    state = %{
      max_entries: max_entries,
      max_memory_bytes: max_memory_mb * 1024 * 1024,
      ttl_seconds: ttl_seconds,
      eviction_policy: eviction_policy
    }

    Logger.info("CompilationCache started",
      max_entries: max_entries,
      max_memory_mb: max_memory_mb,
      ttl_seconds: ttl_seconds,
      eviction_policy: eviction_policy
    )

    # Schedule periodic cleanup if TTL is enabled
    if ttl_seconds > 0 do
      # Clean up every quarter TTL
      schedule_cleanup(div(ttl_seconds * 1000, 4))
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:cache_put, checksum, tenant_id, ir}, _from, state) do
    now = DateTime.utc_now()

    expires_at =
      if state.ttl_seconds > 0 do
        DateTime.add(now, state.ttl_seconds, :second)
      else
        nil
      end

    entry = %CacheEntry{
      checksum: checksum,
      tenant_id: tenant_id,
      ir: ir,
      compiled_at: now,
      expires_at: expires_at,
      access_count: 1,
      last_accessed: now
    }

    :ets.insert(@table_name, {{checksum, tenant_id}, entry})

    # Check if eviction is needed
    check_eviction(state)

    update_stats(fn stats ->
      %{
        stats
        | total_entries: :ets.info(@table_name, :size),
          memory_usage: :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)
      }
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:clear_tenant, tenant_id}, _from, state) do
    # Find all entries for this tenant using match_delete
    pattern = {{:_, tenant_id}, :_}
    count = :ets.select_delete(@table_name, [{pattern, [], [true]}])

    Logger.info("Cleared #{count} cache entries for tenant: #{tenant_id}")

    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_call(:clear_all, _from, state) do
    count = :ets.info(@table_name, :size)
    :ets.delete_all_objects(@table_name)

    # Reset stats
    :ets.insert(@cache_stats, {:stats, Stats.new()})

    Logger.info("Cleared all #{count} cache entries")

    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_cast(:cache_hit, state) do
    update_stats(fn stats -> %{stats | hits: stats.hits + 1} end)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:cache_miss, state) do
    update_stats(fn stats -> %{stats | misses: stats.misses + 1} end)
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    cleanup_expired_entries()

    # Schedule next cleanup if TTL is enabled
    if state.ttl_seconds > 0 do
      schedule_cleanup(div(state.ttl_seconds * 1000, 4))
    end

    {:noreply, state}
  end

  # Private helpers

  defp update_stats(update_fn) do
    case :ets.lookup(@cache_stats, :stats) do
      [{:stats, current_stats}] ->
        new_stats = update_fn.(current_stats)
        :ets.insert(@cache_stats, {:stats, new_stats})

      [] ->
        new_stats = update_fn.(Stats.new())
        :ets.insert(@cache_stats, {:stats, new_stats})
    end
  end

  defp check_eviction(state) do
    entry_count = :ets.info(@table_name, :size)
    memory_bytes = :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)

    cond do
      entry_count > state.max_entries ->
        evict_entries(:count, entry_count - state.max_entries, state.eviction_policy)

      memory_bytes > state.max_memory_bytes ->
        # Evict 10% of entries when memory limit is exceeded
        evict_count = max(1, div(entry_count, 10))
        evict_entries(:memory, evict_count, state.eviction_policy)

      true ->
        :ok
    end
  end

  defp evict_entries(_reason, 0, _policy), do: :ok

  defp evict_entries(reason, count, policy) do
    # Get all entries
    all_entries = :ets.tab2list(@table_name)

    # Sort by eviction policy
    sorted_entries =
      case policy do
        :lru ->
          Enum.sort_by(all_entries, fn {_key, entry} -> entry.last_accessed end)

        :lfu ->
          Enum.sort_by(all_entries, fn {_key, entry} -> entry.access_count end)

        :ttl ->
          # Sort by expiration time, with nil expires_at coming last
          Enum.sort_by(all_entries, fn {_key, entry} ->
            if entry.expires_at do
              DateTime.to_unix(entry.expires_at)
            else
              :infinity
            end
          end)
      end

    # Evict the oldest/least frequent
    entries_to_evict = Enum.take(sorted_entries, count)

    Enum.each(entries_to_evict, fn {key, _entry} ->
      :ets.delete(@table_name, key)
    end)

    update_stats(fn stats -> %{stats | evictions: stats.evictions + count} end)

    Logger.debug("Evicted #{count} cache entries",
      reason: reason,
      policy: policy,
      remaining_entries: :ets.info(@table_name, :size)
    )
  end

  defp schedule_cleanup(delay_ms) do
    Process.send_after(self(), :cleanup_expired, delay_ms)
  end

  defp cleanup_expired_entries do
    now = DateTime.utc_now()

    # Find all expired entries
    all_entries = :ets.tab2list(@table_name)

    expired_entries =
      Enum.filter(all_entries, fn {_key, entry} ->
        entry.expires_at && DateTime.compare(now, entry.expires_at) == :gt
      end)

    # Remove expired entries
    count = length(expired_entries)

    if count > 0 do
      Enum.each(expired_entries, fn {key, _entry} ->
        :ets.delete(@table_name, key)
      end)

      update_stats(fn stats -> %{stats | evictions: stats.evictions + count} end)

      Logger.debug("Cleaned up #{count} expired cache entries")
    end

    count
  end
end
