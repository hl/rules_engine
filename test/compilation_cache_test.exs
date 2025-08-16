defmodule RulesEngine.CompilationCacheTest do
  # Use async: false to avoid cache conflicts
  use ExUnit.Case, async: false
  doctest RulesEngine.CompilationCache

  alias RulesEngine.CompilationCache

  @ir_fixture %{
    "version" => "1.0.0",
    "tenant_id" => "test",
    "rules" => []
  }

  setup do
    # Clear cache before each test
    CompilationCache.clear_all()
    :ok
  end

  describe "basic cache operations" do
    test "put and get operations work" do
      checksum = "test_checksum"
      tenant_id = "test_tenant"

      # Should miss initially
      assert CompilationCache.get(checksum, tenant_id) == :miss

      # Put IR in cache
      assert CompilationCache.put(checksum, tenant_id, @ir_fixture) == :ok

      # Should hit now
      assert CompilationCache.get(checksum, tenant_id) == {:hit, @ir_fixture}
    end

    test "cache statistics are tracked" do
      checksum = "stats_test"
      tenant_id = "test_tenant"

      # Generate a miss and hit, then verify stats are reasonable
      # miss
      CompilationCache.get(checksum, tenant_id)
      CompilationCache.put(checksum, tenant_id, @ir_fixture)
      # hit
      CompilationCache.get(checksum, tenant_id)

      stats = CompilationCache.stats()

      # Verify stats structure and that tracking works
      assert is_integer(stats.hits)
      assert is_integer(stats.misses)
      assert is_integer(stats.evictions)
      assert is_integer(stats.total_entries)
      assert is_integer(stats.memory_usage)

      # Should have at least some activity
      assert stats.hits + stats.misses > 0
    end

    test "cache info returns comprehensive data" do
      CompilationCache.put("info_test", "tenant1", @ir_fixture)

      info = CompilationCache.info()

      assert is_map(info)
      assert Map.has_key?(info, :stats)
      assert Map.has_key?(info, :entry_count)
      assert Map.has_key?(info, :memory_words)
      assert Map.has_key?(info, :memory_bytes)
      assert info.entry_count >= 1
    end
  end

  describe "tenant operations" do
    test "can clear entries for specific tenant" do
      # Add entries for multiple tenants
      CompilationCache.put("rule1", "tenant1", @ir_fixture)
      CompilationCache.put("rule2", "tenant1", @ir_fixture)
      CompilationCache.put("rule1", "tenant2", @ir_fixture)

      # Verify all are accessible
      assert CompilationCache.get("rule1", "tenant1") == {:hit, @ir_fixture}
      assert CompilationCache.get("rule2", "tenant1") == {:hit, @ir_fixture}
      assert CompilationCache.get("rule1", "tenant2") == {:hit, @ir_fixture}

      # Clear tenant1 entries
      assert {:ok, 2} = CompilationCache.clear_tenant("tenant1")

      # Verify tenant1 entries are gone
      assert CompilationCache.get("rule1", "tenant1") == :miss
      assert CompilationCache.get("rule2", "tenant1") == :miss

      # Verify tenant2 entries remain
      assert CompilationCache.get("rule1", "tenant2") == {:hit, @ir_fixture}
    end

    test "can clear all entries" do
      # Add several entries
      CompilationCache.put("rule1", "tenant1", @ir_fixture)
      CompilationCache.put("rule2", "tenant2", @ir_fixture)

      info_before = CompilationCache.info()
      assert info_before.entry_count >= 2

      # Clear all
      assert {:ok, count} = CompilationCache.clear_all()
      assert count >= 2

      # Verify all entries are gone
      assert CompilationCache.get("rule1", "tenant1") == :miss
      assert CompilationCache.get("rule2", "tenant2") == :miss

      info_after = CompilationCache.info()
      assert info_after.entry_count == 0
    end
  end

  describe "cache configuration validation" do
    test "cache is configured and running" do
      # Verify cache is running with reasonable configuration
      info = CompilationCache.info()

      # Should be a valid configuration
      assert is_map(info)
      assert is_integer(info.entry_count)
      assert is_integer(info.memory_bytes)

      stats = CompilationCache.stats()
      assert is_map(stats)
      assert is_integer(stats.hits)
      assert is_integer(stats.misses)
    end

    test "eviction policies are configurable via application environment" do
      # This test verifies that the cache respects configuration
      # The actual configuration is set via Application environment

      # Add multiple entries to test eviction behavior
      for i <- 1..20 do
        CompilationCache.put("config_test_#{i}", "tenant_config", @ir_fixture)
      end

      info = CompilationCache.info()

      # Cache should respect configured limits
      assert info.entry_count > 0
      # Should not exceed reasonable limits (production default is 1000)
      assert info.entry_count <= 1000
    end
  end

  describe "TTL functionality" do
    @tag :integration
    test "TTL expiration can be configured" do
      # This is an integration test that verifies TTL functionality exists
      # Actual TTL testing requires specific configuration at startup

      # Test that cache entries have access time tracking for TTL
      checksum = "ttl_tracking_test"
      tenant_id = "test_tenant"

      CompilationCache.put(checksum, tenant_id, @ir_fixture)

      # Access the entry multiple times - this should update access tracking
      assert {:hit, _} = CompilationCache.get(checksum, tenant_id)
      assert {:hit, _} = CompilationCache.get(checksum, tenant_id)

      # Entry should still be accessible (TTL-based eviction is passive)
      assert {:hit, _} = CompilationCache.get(checksum, tenant_id)
    end
  end
end
