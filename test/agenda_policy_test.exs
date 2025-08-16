defmodule RulesEngine.AgendaPolicyTest do
  use ExUnit.Case, async: true

  alias RulesEngine.Engine.{
    Activation,
    AgendaPolicyRegistry,
    DefaultAgendaPolicy,
    FifoAgendaPolicy,
    LifoAgendaPolicy,
    SalienceOnlyAgendaPolicy
  }

  describe "AgendaPolicyRegistry" do
    test "lists built-in policies" do
      policies = AgendaPolicyRegistry.list_policies()

      assert Keyword.has_key?(policies, :default)
      assert Keyword.has_key?(policies, :fifo)
      assert Keyword.has_key?(policies, :lifo)
      assert Keyword.has_key?(policies, :salience_only)
    end

    test "resolves built-in policies by atom" do
      assert {:ok, DefaultAgendaPolicy} = AgendaPolicyRegistry.resolve_policy(:default)
      assert {:ok, FifoAgendaPolicy} = AgendaPolicyRegistry.resolve_policy(:fifo)
      assert {:ok, LifoAgendaPolicy} = AgendaPolicyRegistry.resolve_policy(:lifo)
      assert {:ok, SalienceOnlyAgendaPolicy} = AgendaPolicyRegistry.resolve_policy(:salience_only)
    end

    test "resolves custom policy modules" do
      assert {:ok, DefaultAgendaPolicy} = AgendaPolicyRegistry.resolve_policy(DefaultAgendaPolicy)
    end

    test "returns error for unknown policies" do
      assert {:error, :unknown_policy} = AgendaPolicyRegistry.resolve_policy(:unknown)
      assert {:error, :unknown_policy} = AgendaPolicyRegistry.resolve_policy(NonExistentModule)
    end

    test "gets policy information" do
      assert {:ok, info} = AgendaPolicyRegistry.policy_info(DefaultAgendaPolicy)
      assert %{name: name, description: description, module: DefaultAgendaPolicy} = info
      assert is_binary(name)
      assert is_binary(description)
    end

    test "lists all policy information" do
      policies = AgendaPolicyRegistry.list_policy_info()
      assert length(policies) == 4

      names = Enum.map(policies, & &1.name)
      assert "default_salience_recency_specificity" in names
      assert "fifo" in names
      assert "lifo" in names
      assert "salience_only" in names
    end
  end

  describe "agenda policy behaviour" do
    setup do
      now = DateTime.utc_now()
      earlier = DateTime.add(now, -1, :second)
      later = DateTime.add(now, 1, :second)

      activations = [
        %Activation{
          production_id: "rule1",
          token: %{},
          salience: 100,
          specificity: 2,
          inserted_at: now,
          rule_metadata: %{}
        },
        %Activation{
          production_id: "rule2",
          token: %{},
          salience: 50,
          specificity: 3,
          inserted_at: earlier,
          rule_metadata: %{}
        },
        %Activation{
          production_id: "rule3",
          token: %{},
          salience: 100,
          specificity: 1,
          inserted_at: later,
          rule_metadata: %{}
        }
      ]

      %{activations: activations}
    end

    test "DefaultAgendaPolicy orders by salience, specificity, recency", %{
      activations: [act1, act2, act3]
    } do
      policy = DefaultAgendaPolicy

      # Higher salience wins
      assert policy.compare(act1, act2) == true
      assert policy.compare(act2, act1) == false

      # Same salience, higher specificity wins
      assert policy.compare(act1, act3) == true
      assert policy.compare(act3, act1) == false

      # Rule2 (older) vs rule3 (newer) - both have different salience/specificity
      # Higher salience wins
      assert policy.compare(act3, act2) == true
    end

    test "FifoAgendaPolicy orders by insertion time (oldest first)", %{
      activations: [act1, act2, act3]
    } do
      policy = FifoAgendaPolicy

      # Earlier insertion time wins
      # earlier before now
      assert policy.compare(act2, act1) == true
      assert policy.compare(act1, act2) == false
      # now before later
      assert policy.compare(act1, act3) == true
      assert policy.compare(act3, act1) == false
    end

    test "LifoAgendaPolicy orders by insertion time (newest first)", %{
      activations: [act1, act2, act3]
    } do
      policy = LifoAgendaPolicy

      # Later insertion time wins
      # later after now
      assert policy.compare(act3, act1) == true
      assert policy.compare(act1, act3) == false
      # now after earlier
      assert policy.compare(act1, act2) == true
      assert policy.compare(act2, act1) == false
    end

    test "SalienceOnlyAgendaPolicy orders by salience then production_id", %{
      activations: [act1, act2, act3]
    } do
      policy = SalienceOnlyAgendaPolicy

      # Higher salience wins
      assert policy.compare(act1, act2) == true
      assert policy.compare(act2, act1) == false

      # Same salience, lexical production_id wins
      # "rule1" < "rule3"
      assert policy.compare(act1, act3) == true
      assert policy.compare(act3, act1) == false
    end
  end
end
