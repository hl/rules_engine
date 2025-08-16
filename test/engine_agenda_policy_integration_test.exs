defmodule RulesEngine.EngineAgendaPolicyIntegrationTest do
  use ExUnit.Case, async: true

  alias RulesEngine.Engine
  alias RulesEngine.Engine.{AgendaPolicyRegistry, FifoAgendaPolicy, LifoAgendaPolicy}

  # Simple network for testing agenda policies
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

  describe "engine agenda policy configuration" do
    test "uses default policy when not specified" do
      {:ok, engine} = Engine.start_tenant(:test_tenant_default, @test_network)

      # Get the engine state snapshot to check policy
      state = :sys.get_state(engine)
      assert state.agenda.policy == RulesEngine.Engine.DefaultAgendaPolicy

      :ok = Engine.stop_tenant(:test_tenant_default)
    end

    test "uses specified built-in policy by atom" do
      {:ok, engine} = Engine.start_tenant(:test_tenant_fifo, @test_network, agenda_policy: :fifo)

      state = :sys.get_state(engine)
      assert state.agenda.policy == FifoAgendaPolicy

      :ok = Engine.stop_tenant(:test_tenant_fifo)
    end

    test "uses specified built-in policy by module" do
      {:ok, engine} =
        Engine.start_tenant(:test_tenant_lifo, @test_network, agenda_policy: LifoAgendaPolicy)

      state = :sys.get_state(engine)
      assert state.agenda.policy == LifoAgendaPolicy

      :ok = Engine.stop_tenant(:test_tenant_lifo)
    end

    test "falls back to default for unknown policy with warning" do
      # Capture logs to verify warning is logged
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, engine} =
          Engine.start_tenant(:test_tenant_unknown, @test_network, agenda_policy: :unknown)

        state = :sys.get_state(engine)
        assert state.agenda.policy == RulesEngine.Engine.DefaultAgendaPolicy

        :ok = Engine.stop_tenant(:test_tenant_unknown)
      end) =~ "Unknown agenda policy :unknown"
    end
  end

  describe "policy registry integration" do
    test "engine can discover available policies" do
      policies = AgendaPolicyRegistry.list_policies()
      assert length(policies) >= 4

      policy_names = policies |> Keyword.keys() |> Enum.sort()
      expected_names = [:default, :fifo, :lifo, :salience_only] |> Enum.sort()

      assert policy_names == expected_names
    end

    test "engine can get policy information" do
      policies_info = AgendaPolicyRegistry.list_policy_info()
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
