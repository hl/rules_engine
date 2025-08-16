defmodule RulesEngine.EnginePredicateRegistryTest do
  use ExUnit.Case, async: false

  alias RulesEngine.Engine.{PredicateProvider, PredicateRegistry}

  # Test predicate provider implementation
  defmodule TestPredicateProvider do
    @behaviour PredicateProvider

    @supported_ops [:custom_equals, :domain_check, :expensive_calculation]

    @impl true
    def supported_ops, do: @supported_ops

    @impl true
    def evaluate(:custom_equals, left, right), do: left == right
    def evaluate(:domain_check, value, domain) when is_list(domain), do: value in domain
    def evaluate(:expensive_calculation, a, b) when is_number(a) and is_number(b), do: a * b > 100

    @impl true
    def expectations(:custom_equals), do: %{}
    def expectations(:domain_check), do: %{collection_right?: true}
    def expectations(:expensive_calculation), do: %{numeric_left?: true, numeric_right?: true}

    @impl true
    def indexable?(:custom_equals), do: true
    def indexable?(_), do: false

    @impl true
    def selectivity_hint(:custom_equals), do: 0.01
    def selectivity_hint(:domain_check), do: 0.2
    def selectivity_hint(:expensive_calculation), do: 0.8
  end

  defmodule InvalidProvider do
    # Missing behaviour declaration
    def supported_ops, do: [:invalid_op]
    def evaluate(:invalid_op, _a, _b), do: true
  end

  setup do
    # Clean up any registered providers before each test
    PredicateRegistry.list_providers()
    |> Enum.each(fn {provider, _ops} ->
      if provider != RulesEngine.Predicates do
        PredicateRegistry.unregister_provider(provider)
      end
    end)

    :ok
  end

  describe "built-in predicates" do
    test "registry starts with all built-in predicates" do
      ops = PredicateRegistry.supported_ops()

      # Should include all standard predicates
      assert :== in ops
      assert :!= in ops
      assert :> in ops
      assert :< in ops
      assert :in in ops
      assert :starts_with in ops
      assert :before in ops
      assert :size_eq in ops
      assert :approximately in ops
    end

    test "built-in predicates work correctly" do
      assert PredicateRegistry.evaluate(:==, "hello", "hello")
      refute PredicateRegistry.evaluate(:==, "hello", "world")

      assert PredicateRegistry.evaluate(:starts_with, "hello world", "hello")
      refute PredicateRegistry.evaluate(:starts_with, "hello world", "world")
    end

    test "built-in predicate metadata" do
      assert PredicateRegistry.expectations(:before) == %{datetime_required?: true}

      assert PredicateRegistry.expectations(:size_eq) == %{
               collection_left?: true,
               numeric_right?: true
             }

      assert PredicateRegistry.indexable?(:==)
      refute PredicateRegistry.indexable?(:contains)

      assert PredicateRegistry.selectivity_hint(:==) == 0.01
      assert PredicateRegistry.selectivity_hint(:contains) == 0.3
    end
  end

  describe "custom predicate registration" do
    test "can register a custom predicate provider" do
      assert :ok = PredicateRegistry.register_provider(TestPredicateProvider)

      ops = PredicateRegistry.supported_ops()
      assert :custom_equals in ops
      assert :domain_check in ops
      assert :expensive_calculation in ops
    end

    test "custom predicates are evaluated correctly" do
      :ok = PredicateRegistry.register_provider(TestPredicateProvider)

      assert PredicateRegistry.evaluate(:custom_equals, 42, 42)
      refute PredicateRegistry.evaluate(:custom_equals, 42, 43)

      assert PredicateRegistry.evaluate(:domain_check, "apple", ["apple", "banana", "cherry"])
      refute PredicateRegistry.evaluate(:domain_check, "grape", ["apple", "banana", "cherry"])

      # 10 * 20 = 200 > 100
      assert PredicateRegistry.evaluate(:expensive_calculation, 10, 20)
      # 5 * 10 = 50 < 100
      refute PredicateRegistry.evaluate(:expensive_calculation, 5, 10)
    end

    test "custom predicate metadata is accessible" do
      :ok = PredicateRegistry.register_provider(TestPredicateProvider)

      assert PredicateRegistry.expectations(:domain_check) == %{collection_right?: true}

      assert PredicateRegistry.expectations(:expensive_calculation) == %{
               numeric_left?: true,
               numeric_right?: true
             }

      assert PredicateRegistry.indexable?(:custom_equals)
      refute PredicateRegistry.indexable?(:domain_check)

      assert PredicateRegistry.selectivity_hint(:custom_equals) == 0.01
      assert PredicateRegistry.selectivity_hint(:domain_check) == 0.2
      assert PredicateRegistry.selectivity_hint(:expensive_calculation) == 0.8
    end

    test "can unregister a custom predicate provider" do
      :ok = PredicateRegistry.register_provider(TestPredicateProvider)
      assert :custom_equals in PredicateRegistry.supported_ops()

      :ok = PredicateRegistry.unregister_provider(TestPredicateProvider)
      refute :custom_equals in PredicateRegistry.supported_ops()
    end

    test "provider registration prevents conflicts" do
      # Register the provider once
      :ok = PredicateRegistry.register_provider(TestPredicateProvider)

      # Try to register again - should detect conflicts
      assert {:error, {:conflicts, [:custom_equals, :domain_check, :expensive_calculation]}} =
               PredicateRegistry.register_provider(TestPredicateProvider)
    end

    test "rejects invalid provider modules" do
      assert {:error, :missing_behaviour} = PredicateRegistry.register_provider(InvalidProvider)
      assert {:error, :module_not_found} = PredicateRegistry.register_provider(NonExistentModule)
    end
  end

  describe "predicate discovery" do
    test "list_providers shows registered providers" do
      :ok = PredicateRegistry.register_provider(TestPredicateProvider)

      providers = PredicateRegistry.list_providers()

      assert {TestPredicateProvider, [:custom_equals, :domain_check, :expensive_calculation]} in providers
    end

    test "predicate_info provides detailed information" do
      :ok = PredicateRegistry.register_provider(TestPredicateProvider)

      {:ok, info} = PredicateRegistry.predicate_info(:custom_equals)
      assert info.operation == :custom_equals
      assert info.provider == TestPredicateProvider
      assert info.indexable? == true
      assert info.selectivity_hint == 0.01
      assert info.built_in? == false

      # Built-in predicate info
      {:ok, builtin_info} = PredicateRegistry.predicate_info(:==)
      assert builtin_info.provider == RulesEngine.Predicates
      assert builtin_info.built_in? == true

      # Unknown predicate
      assert {:error, :not_found} = PredicateRegistry.predicate_info(:unknown_predicate)
    end

    test "supported? checks both built-in and custom predicates" do
      # Built-in predicate
      assert PredicateRegistry.supported?(:==)

      # Custom predicate not yet registered
      refute PredicateRegistry.supported?(:custom_equals)

      # Register custom provider
      :ok = PredicateRegistry.register_provider(TestPredicateProvider)

      # Now custom predicate is supported
      assert PredicateRegistry.supported?(:custom_equals)
    end
  end

  describe "error handling" do
    test "evaluation errors are handled gracefully" do
      # This should fail because TestPredicateProvider expects lists for domain_check
      :ok = PredicateRegistry.register_provider(TestPredicateProvider)

      assert {:error, {:evaluation_failed, _}} =
               PredicateRegistry.evaluate(:domain_check, "value", :not_a_list)
    end

    test "unknown predicate evaluation returns error" do
      assert {:error, {:unknown_predicate, :unknown_op}} =
               PredicateRegistry.evaluate(:unknown_op, "a", "b")
    end

    test "default values for unknown predicates" do
      # Unknown predicates return sensible defaults
      assert PredicateRegistry.expectations(:unknown_op) == %{}
      refute PredicateRegistry.indexable?(:unknown_op)
      assert PredicateRegistry.selectivity_hint(:unknown_op) == 0.5
    end
  end

  describe "integration with validation" do
    test "validation uses predicate registry for supported operations" do
      alias RulesEngine.DSL.Validate

      # Register custom provider
      :ok = PredicateRegistry.register_provider(TestPredicateProvider)

      # Test AST with custom predicate
      ast = [
        %{
          name: "test-rule",
          when:
            {:when,
             [
               {:fact, :entry, "Entry", []},
               {:guard, {:cmp, :custom_equals, {:binding, :entry, :value}, 42}}
             ]},
          then:
            {:then,
             [
               {:emit, "Result", [value: 1]}
             ]}
        }
      ]

      # Should validate successfully with custom predicate
      assert {:ok, _} = Validate.validate(ast, %{})
    end
  end
end
