defmodule RulesEngine.EngineRefractionPolicyIntegrationTest do
  use ExUnit.Case, async: true

  alias RulesEngine.Engine
  alias RulesEngine.Engine.{NoRefractionPolicy, PerRuleRefractionPolicy, RefractionPolicyRegistry}

  # Simple network for testing refraction policies
  @test_network %{
    "alpha_nodes" => %{},
    "beta_nodes" => %{},
    "production_nodes" => %{
      "prod1" => %{
        "rule_id" => "test-rule-1",
        "salience" => 100,
        "actions" => []
      },
      "prod2" => %{
        "rule_id" => "test-rule-2",
        "salience" => 50,
        "actions" => []
      }
    },
    "agenda_policy" => %{
      "name" => "default",
      "salience_priority" => true,
      "recency_tiebreaker" => true
    },
    "refraction" => %{
      "policy" => "per_activation",
      "duration" => "session"
    }
  }

  describe "engine refraction policy configuration" do
    test "uses default policy when not specified" do
      {:ok, engine} = Engine.start_tenant(:test_tenant_default_refraction, @test_network)

      # Get the engine state snapshot to check policy
      state = :sys.get_state(engine)
      assert state.refraction_policy == RulesEngine.Engine.DefaultRefractionPolicy

      :ok = Engine.stop_tenant(:test_tenant_default_refraction)
    end

    test "uses specified built-in policy by atom" do
      {:ok, engine} =
        Engine.start_tenant(:test_tenant_none_refraction, @test_network, refraction_policy: :none)

      state = :sys.get_state(engine)
      assert state.refraction_policy == NoRefractionPolicy

      :ok = Engine.stop_tenant(:test_tenant_none_refraction)
    end

    test "uses specified built-in policy by module" do
      {:ok, engine} =
        Engine.start_tenant(:test_tenant_per_rule_refraction, @test_network,
          refraction_policy: PerRuleRefractionPolicy
        )

      state = :sys.get_state(engine)
      assert state.refraction_policy == PerRuleRefractionPolicy

      :ok = Engine.stop_tenant(:test_tenant_per_rule_refraction)
    end

    test "uses TTL policy with custom options" do
      opts = [refraction_policy: :ttl, refraction_opts: [ttl_seconds: 1800]]
      {:ok, engine} = Engine.start_tenant(:test_tenant_ttl_refraction, @test_network, opts)

      state = :sys.get_state(engine)
      assert state.refraction_policy == RulesEngine.Engine.TtlRefractionPolicy
      assert state.refraction_opts == [ttl_seconds: 1800]

      :ok = Engine.stop_tenant(:test_tenant_ttl_refraction)
    end

    test "falls back to default for unknown policy with warning" do
      # Capture logs to verify warning is logged
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, engine} =
          Engine.start_tenant(:test_tenant_unknown_refraction, @test_network,
            refraction_policy: :unknown
          )

        state = :sys.get_state(engine)
        assert state.refraction_policy == RulesEngine.Engine.DefaultRefractionPolicy

        :ok = Engine.stop_tenant(:test_tenant_unknown_refraction)
      end) =~ "Unknown refraction policy :unknown"
    end
  end

  describe "policy registry integration" do
    test "engine can discover available refraction policies" do
      policies = RefractionPolicyRegistry.list_policies()
      assert length(policies) >= 4

      policy_names = policies |> Keyword.keys() |> Enum.sort()
      expected_names = [:default, :none, :per_rule, :ttl] |> Enum.sort()

      assert policy_names == expected_names
    end

    test "engine can get refraction policy information" do
      policies_info = RefractionPolicyRegistry.list_policy_info()
      assert length(policies_info) == 4

      # Verify each policy has required metadata
      for policy_info <- policies_info do
        assert is_binary(policy_info.name)
        assert is_binary(policy_info.description)
        assert is_atom(policy_info.module)
      end
    end
  end
end
