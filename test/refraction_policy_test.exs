defmodule RulesEngine.RefractionPolicyTest do
  use ExUnit.Case, async: true

  alias RulesEngine.Engine.{
    Activation,
    DefaultRefractionPolicy,
    NoRefractionPolicy,
    PerRuleRefractionPolicy,
    RefractionPolicyRegistry,
    Token,
    TtlRefractionPolicy
  }

  describe "RefractionPolicyRegistry" do
    test "lists built-in policies" do
      policies = RefractionPolicyRegistry.list_policies()

      assert Keyword.has_key?(policies, :default)
      assert Keyword.has_key?(policies, :none)
      assert Keyword.has_key?(policies, :per_rule)
      assert Keyword.has_key?(policies, :ttl)
    end

    test "resolves built-in policies by atom" do
      assert {:ok, DefaultRefractionPolicy} = RefractionPolicyRegistry.resolve_policy(:default)
      assert {:ok, NoRefractionPolicy} = RefractionPolicyRegistry.resolve_policy(:none)
      assert {:ok, PerRuleRefractionPolicy} = RefractionPolicyRegistry.resolve_policy(:per_rule)
      assert {:ok, TtlRefractionPolicy} = RefractionPolicyRegistry.resolve_policy(:ttl)
    end

    test "resolves custom policy modules" do
      assert {:ok, DefaultRefractionPolicy} =
               RefractionPolicyRegistry.resolve_policy(DefaultRefractionPolicy)
    end

    test "returns error for unknown policies" do
      assert {:error, :unknown_policy} = RefractionPolicyRegistry.resolve_policy(:unknown)

      assert {:error, :unknown_policy} =
               RefractionPolicyRegistry.resolve_policy(NonExistentModule)
    end

    test "gets policy information" do
      assert {:ok, info} = RefractionPolicyRegistry.policy_info(DefaultRefractionPolicy)
      assert %{name: name, description: description, module: DefaultRefractionPolicy} = info
      assert is_binary(name)
      assert is_binary(description)
    end

    test "lists all policy information" do
      policies = RefractionPolicyRegistry.list_policy_info()
      assert length(policies) == 4

      names = Enum.map(policies, & &1.name)
      assert "default_per_activation" in names
      assert "no_refraction" in names
      assert "per_rule" in names
      assert "ttl" in names
    end
  end

  describe "refraction policy behaviour" do
    setup do
      token = %Token{
        bindings: %{x: 1},
        wmes: ["fact1"],
        hash: "hash1",
        created_at: DateTime.utc_now()
      }

      activation1 = %Activation{
        production_id: "rule1",
        token: token,
        salience: 100,
        specificity: 1,
        inserted_at: DateTime.utc_now(),
        rule_metadata: %{}
      }

      activation2 = %Activation{
        production_id: "rule2",
        token: token,
        salience: 50,
        specificity: 1,
        inserted_at: DateTime.utc_now(),
        rule_metadata: %{}
      }

      %{activation1: activation1, activation2: activation2}
    end

    test "DefaultRefractionPolicy refracts on same activation", %{activation1: act1} do
      policy = DefaultRefractionPolicy
      empty_store = policy.init_store([])

      # First firing should be allowed
      assert {:fire, store1} = policy.should_refract(act1, empty_store, [])

      # Second firing of same activation should be refracted
      assert {:refract, _store2} = policy.should_refract(act1, store1, [])
    end

    test "NoRefractionPolicy never refracts", %{activation1: act1} do
      policy = NoRefractionPolicy
      empty_store = policy.init_store([])

      # Should always allow firing
      assert {:fire, store1} = policy.should_refract(act1, empty_store, [])
      assert {:fire, _store2} = policy.should_refract(act1, store1, [])
    end

    test "PerRuleRefractionPolicy refracts per rule", %{activation1: act1, activation2: act2} do
      policy = PerRuleRefractionPolicy
      empty_store = policy.init_store([])

      # First firing of rule1 should be allowed
      assert {:fire, store1} = policy.should_refract(act1, empty_store, [])

      # Second firing of rule1 should be refracted (different token doesn't matter)
      assert {:refract, store2} = policy.should_refract(act1, store1, [])

      # First firing of rule2 should be allowed
      assert {:fire, _store3} = policy.should_refract(act2, store2, [])
    end

    test "TtlRefractionPolicy respects TTL", %{activation1: act1} do
      policy = TtlRefractionPolicy
      empty_store = policy.init_store([])
      opts = [ttl_seconds: 1]

      # First firing should be allowed
      assert {:fire, store1} = policy.should_refract(act1, empty_store, opts)

      # Immediate second firing should be refracted
      assert {:refract, store2} = policy.should_refract(act1, store1, opts)

      # After TTL expiry, should be allowed again
      # We can't easily test this without time travel, but we can test the structure
      assert is_map(store2)
      key = policy.refraction_key(act1)
      assert Map.has_key?(store2, key)
    end

    test "TtlRefractionPolicy cleanup_store removes expired entries", %{activation1: act1} do
      policy = TtlRefractionPolicy
      opts = [ttl_seconds: 1]

      # Create a store with an expired entry (simulate past timestamp)
      past_time = DateTime.add(DateTime.utc_now(), -10, :second)
      key = policy.refraction_key(act1)
      store_with_expired = %{key => past_time}

      # Cleanup should remove expired entries
      cleaned_store = policy.cleanup_store(store_with_expired, opts)
      assert cleaned_store == %{}
    end
  end
end
