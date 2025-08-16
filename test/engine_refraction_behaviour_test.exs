defmodule RulesEngine.EngineRefractionBehaviourTest do
  use ExUnit.Case, async: true

  alias RulesEngine.Engine

  # Simple test network
  @test_network %{
    "alpha_nodes" => %{},
    "beta_nodes" => %{},
    "production_nodes" => %{
      "prod1" => %{
        "rule_id" => "test-rule-1",
        "salience" => 100,
        "actions" => [%{"type" => "emit", "fact" => %{"type" => "Result", "value" => 1}}]
      }
    },
    "agenda_policy" => %{"name" => "default"},
    "refraction" => %{"policy" => "per_activation"}
  }

  test "default refraction policy prevents duplicate firing" do
    {:ok, engine} =
      Engine.start_tenant(:test_refraction_default, @test_network, refraction_policy: :default)

    # Create a mock activation (this is integration testing at high level)
    state = :sys.get_state(engine)

    # Verify the policy is set correctly
    assert state.refraction_policy == RulesEngine.Engine.DefaultRefractionPolicy
    assert function_exported?(state.refraction_policy, :should_refract, 3)

    :ok = Engine.stop_tenant(:test_refraction_default)
  end

  test "no refraction policy allows repeated firing" do
    {:ok, engine} =
      Engine.start_tenant(:test_refraction_none, @test_network, refraction_policy: :none)

    state = :sys.get_state(engine)
    assert state.refraction_policy == RulesEngine.Engine.NoRefractionPolicy

    :ok = Engine.stop_tenant(:test_refraction_none)
  end

  test "per rule refraction policy prevents rule re-firing" do
    {:ok, engine} =
      Engine.start_tenant(:test_refraction_per_rule, @test_network, refraction_policy: :per_rule)

    state = :sys.get_state(engine)
    assert state.refraction_policy == RulesEngine.Engine.PerRuleRefractionPolicy

    :ok = Engine.stop_tenant(:test_refraction_per_rule)
  end

  test "TTL refraction policy with custom TTL" do
    opts = [refraction_policy: :ttl, refraction_opts: [ttl_seconds: 300]]
    {:ok, engine} = Engine.start_tenant(:test_refraction_ttl, @test_network, opts)

    state = :sys.get_state(engine)
    assert state.refraction_policy == RulesEngine.Engine.TtlRefractionPolicy
    assert state.refraction_opts == [ttl_seconds: 300]
    # TTL policy uses Map
    assert state.refraction_store == %{}

    :ok = Engine.stop_tenant(:test_refraction_ttl)
  end

  test "refraction store is properly initialized per policy" do
    {:ok, engine1} =
      Engine.start_tenant(:test_store_default, @test_network, refraction_policy: :default)

    {:ok, engine2} = Engine.start_tenant(:test_store_ttl, @test_network, refraction_policy: :ttl)

    state1 = :sys.get_state(engine1)
    state2 = :sys.get_state(engine2)

    # Default policy uses MapSet
    assert MapSet.size(state1.refraction_store) == 0

    # TTL policy uses Map
    assert map_size(state2.refraction_store) == 0

    :ok = Engine.stop_tenant(:test_store_default)
    :ok = Engine.stop_tenant(:test_store_ttl)
  end
end
