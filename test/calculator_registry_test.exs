defmodule RulesEngineTest.CalculatorRegistryTest do
  use ExUnit.Case, async: false

  alias RulesEngine.Engine.{CalculatorProvider, CalculatorRegistry}

  setup do
    # Clean up any test providers that might be left from previous tests
    CalculatorRegistry.unregister_provider(TestCalculatorProvider)
    CalculatorRegistry.unregister_provider(InvalidProvider)
    :ok
  end

  # Test custom calculator provider
  defmodule TestCalculatorProvider do
    @behaviour CalculatorProvider

    @impl true
    def supported_functions do
      [:tax_rate, :business_days, :compound_interest]
    end

    @impl true
    def evaluate(:tax_rate, [state, income]) when is_binary(state) do
      rate =
        case state do
          "CA" -> Decimal.new("0.13")
          "NY" -> Decimal.new("0.08")
          _ -> Decimal.new("0.05")
        end

      Decimal.mult(income, rate)
    end

    def evaluate(:business_days, [start_date, end_date]) do
      # Simple business days calculation (weekdays only)
      diff = Date.diff(end_date, start_date)
      # Approximate: assume 5/7 of days are business days
      round(diff * 5 / 7)
    end

    def evaluate(:compound_interest, [principal, rate, periods]) do
      # A = P(1 + r)^n
      base = Decimal.add(Decimal.new("1"), rate)
      power = :math.pow(Decimal.to_float(base), Decimal.to_float(periods))
      Decimal.mult(principal, Decimal.new(Float.to_string(power)))
    end

    @impl true
    def function_info(:tax_rate) do
      %{
        arity: 2,
        return_type: :decimal,
        description: "Calculate tax based on state and income"
      }
    end

    def function_info(:business_days) do
      %{
        arity: 2,
        return_type: :integer,
        description: "Calculate business days between two dates"
      }
    end

    def function_info(:compound_interest) do
      %{
        arity: 3,
        return_type: :decimal,
        description: "Calculate compound interest"
      }
    end
  end

  # Test invalid provider missing callbacks
  defmodule InvalidProvider do
    def supported_functions, do: [:invalid_func]
    # Missing evaluate/2 and function_info/1 callbacks
  end

  describe "built-in calculator functions" do
    test "registers built-in functions on startup" do
      functions = CalculatorRegistry.list_functions()

      expected_functions = [
        :time_between,
        :overlap_hours,
        :bucket,
        :decimal_add,
        :decimal_subtract,
        :decimal_multiply,
        :dec
      ]

      for func <- expected_functions do
        assert func in functions, "Expected built-in function #{func} to be registered"
      end
    end

    test "provides correct function info for built-ins" do
      {:ok, info} = CalculatorRegistry.function_info(:time_between)
      assert %{arity: 3, return_type: :decimal, provider: RulesEngine.Calculators} = info

      {:ok, info} = CalculatorRegistry.function_info(:bucket)
      assert %{arity: 2, return_type: :tuple, provider: RulesEngine.Calculators} = info

      {:ok, info} = CalculatorRegistry.function_info(:dec)
      assert %{arity: 1, return_type: :decimal, provider: RulesEngine.Calculators} = info
    end

    test "evaluates built-in functions correctly" do
      # Test dec function
      {:ok, result} = CalculatorRegistry.evaluate(:dec, ["12.50"])
      assert Decimal.equal?(result, Decimal.new("12.50"))

      # Test decimal_add function
      {:ok, result} =
        CalculatorRegistry.evaluate(:decimal_add, [Decimal.new("1.50"), Decimal.new("2.25")])

      assert Decimal.equal?(result, Decimal.new("3.75"))

      # Test bucket function
      dt = ~U[2023-01-01 15:30:00Z]
      {:ok, result} = CalculatorRegistry.evaluate(:bucket, [:day, dt])
      assert result == {:day, "Etc/UTC", ~D[2023-01-01]}
    end
  end

  describe "custom calculator registration" do
    test "successfully registers valid provider" do
      # Unregister first in case it's already registered
      CalculatorRegistry.unregister_provider(TestCalculatorProvider)

      assert :ok = CalculatorRegistry.register_provider(TestCalculatorProvider)

      functions = CalculatorRegistry.list_functions()
      assert :tax_rate in functions
      assert :business_days in functions
      assert :compound_interest in functions

      providers = CalculatorRegistry.list_providers()
      assert TestCalculatorProvider in providers
    end

    test "provides function info for custom providers" do
      CalculatorRegistry.register_provider(TestCalculatorProvider)

      {:ok, info} = CalculatorRegistry.function_info(:tax_rate)
      assert %{arity: 2, return_type: :decimal, provider: TestCalculatorProvider} = info

      {:ok, info} = CalculatorRegistry.function_info(:compound_interest)
      assert %{arity: 3, return_type: :decimal, provider: TestCalculatorProvider} = info
    end

    test "evaluates custom functions correctly" do
      CalculatorRegistry.register_provider(TestCalculatorProvider)
      on_exit(fn -> CalculatorRegistry.unregister_provider(TestCalculatorProvider) end)

      # Test tax_rate function
      {:ok, result} = CalculatorRegistry.evaluate(:tax_rate, ["CA", Decimal.new("100")])
      expected = Decimal.mult(Decimal.new("100"), Decimal.new("0.13"))
      assert Decimal.equal?(result, expected)

      # Test business_days function
      # Sunday
      start_date = ~D[2023-01-01]
      # Sunday (7 days later)
      end_date = ~D[2023-01-08]
      {:ok, result} = CalculatorRegistry.evaluate(:business_days, [start_date, end_date])
      # 5 business days in a week
      assert result == 5

      # Test compound_interest function
      principal = Decimal.new("1000")
      rate = Decimal.new("0.05")
      periods = Decimal.new("2")
      {:ok, result} = CalculatorRegistry.evaluate(:compound_interest, [principal, rate, periods])
      # 1000 * (1.05)^2
      expected = Decimal.mult(principal, Decimal.new("1.1025"))
      assert Decimal.equal?(result, expected)
    end

    test "rejects provider with missing callbacks" do
      {:error, {:missing_callbacks, missing}} =
        CalculatorRegistry.register_provider(InvalidProvider)

      assert {:evaluate, 2} in missing
      assert {:function_info, 1} in missing
    end

    test "rejects provider with conflicting function names" do
      CalculatorRegistry.register_provider(TestCalculatorProvider)

      # Try to register the same provider again
      {:error, {:conflicts, conflicts}} =
        CalculatorRegistry.register_provider(TestCalculatorProvider)

      assert :tax_rate in conflicts
      assert :business_days in conflicts
      assert :compound_interest in conflicts
    end

    test "successfully unregisters provider" do
      CalculatorRegistry.register_provider(TestCalculatorProvider)

      # Verify functions are registered
      functions = CalculatorRegistry.list_functions()
      assert :tax_rate in functions

      # Unregister provider
      :ok = CalculatorRegistry.unregister_provider(TestCalculatorProvider)

      # Verify functions are removed
      functions = CalculatorRegistry.list_functions()
      refute :tax_rate in functions
      refute :business_days in functions
      refute :compound_interest in functions

      providers = CalculatorRegistry.list_providers()
      refute TestCalculatorProvider in providers
    end
  end

  describe "function queries" do
    test "supported? returns correct boolean" do
      assert CalculatorRegistry.supported?(:time_between)
      assert CalculatorRegistry.supported?(:dec)
      refute CalculatorRegistry.supported?(:unknown_function)

      CalculatorRegistry.register_provider(TestCalculatorProvider)
      assert CalculatorRegistry.supported?(:tax_rate)

      CalculatorRegistry.unregister_provider(TestCalculatorProvider)
      refute CalculatorRegistry.supported?(:tax_rate)
    end

    test "function_info returns error for unknown functions" do
      {:error, :not_found} = CalculatorRegistry.function_info(:unknown_function)
    end

    test "evaluate returns error for unknown functions" do
      {:error, {:unknown_function, :unknown_func}} =
        CalculatorRegistry.evaluate(:unknown_func, [])
    end

    test "evaluate handles function evaluation errors" do
      CalculatorRegistry.register_provider(TestCalculatorProvider)

      # Pass wrong argument types to cause an error
      {:error, {:evaluation_error, _}} =
        CalculatorRegistry.evaluate(:tax_rate, [123, "not_decimal"])
    end
  end

  describe "integration with validation" do
    test "validation accepts known functions with correct arity" do
      alias RulesEngine.DSL.Parser
      alias RulesEngine.DSL.Validate

      CalculatorRegistry.register_provider(TestCalculatorProvider)

      dsl = """
      rule "tax-calculation" do
        when
          income: Income(amount: amt, state: st)
        then
          emit TaxOwed(amount: tax_rate(st, amt))
      end
      """

      {:ok, ast, []} = Parser.parse(dsl)

      # Provide minimal schemas for validation
      schemas = %{
        "Income" => %{"fields" => ["amount", "state"]},
        "TaxOwed" => %{"fields" => ["amount"]}
      }

      # Validation should pass
      assert {:ok, _validated_ast} = Validate.validate(ast, %{fact_schemas: schemas})
    end

    test "validation rejects unknown functions" do
      alias RulesEngine.DSL.Parser
      alias RulesEngine.DSL.Validate

      dsl = """
      rule "unknown-calculation" do
        when
          data: Data(value: v)
        then
          emit Result(value: unknown_function(v))
      end
      """

      {:ok, ast, []} = Parser.parse(dsl)

      schemas = %{
        "Data" => %{"fields" => ["value"]},
        "Result" => %{"fields" => ["value"]}
      }

      {:error, errors} = Validate.validate(ast, %{fact_schemas: schemas})

      assert Enum.any?(errors, fn error ->
               error.code == :unknown_function and
                 String.contains?(error.message, "unknown_function")
             end)
    end

    test "validation rejects functions with wrong arity" do
      alias RulesEngine.DSL.Parser
      alias RulesEngine.DSL.Validate

      CalculatorRegistry.register_provider(TestCalculatorProvider)

      dsl = """
      rule "wrong-arity" do
        when
          data: Data(value: v)
        then
          emit Result(value: tax_rate(v))
      end
      """

      {:ok, ast, []} = Parser.parse(dsl)

      schemas = %{
        "Data" => %{"fields" => ["value"]},
        "Result" => %{"fields" => ["value"]}
      }

      {:error, errors} = Validate.validate(ast, %{fact_schemas: schemas})

      assert Enum.any?(errors, fn error ->
               error.code == :invalid_arity and
                 String.contains?(error.message, "tax_rate/1") and
                 String.contains?(error.message, "tax_rate/2")
             end)
    end
  end
end
