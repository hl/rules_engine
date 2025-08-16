defmodule RulesEngine.Engine.CalculatorProvider do
  @moduledoc """
  Behaviour for implementing custom calculator functions.

  Calculator providers enable host applications to add domain-specific
  calculation functions that can be used within DSL expressions. This
  allows for extensibility beyond the built-in calculators.

  ## Example Implementation

      defmodule MyApp.CustomCalculators do
        @behaviour RulesEngine.Engine.CalculatorProvider
        
        @impl true
        def supported_functions do
          [:tax_rate, :business_days_between, :compound_interest]
        end
        
        @impl true
        def evaluate(:tax_rate, [state, income]) do
          # Custom tax calculation logic
          case state do
            "CA" -> Decimal.mult(income, Decimal.new("0.13"))
            "NY" -> Decimal.mult(income, Decimal.new("0.08"))
            _ -> Decimal.mult(income, Decimal.new("0.05"))
          end
        end
        
        @impl true
        def evaluate(:business_days_between, [start_date, end_date]) do
          # Business days calculation logic
          calculate_business_days(start_date, end_date)
        end
        
        @impl true
        def evaluate(:compound_interest, [principal, rate, periods]) do
          # Compound interest calculation
          power = Decimal.add(Decimal.new("1"), rate) 
                 |> Decimal.to_float() 
                 |> :math.pow(Decimal.to_float(periods))
          Decimal.mult(principal, Decimal.new(power))
        end
        
        @impl true
        def function_info(:tax_rate) do
          %{
            arity: 2,
            return_type: :decimal,
            description: "Calculate tax based on state and income"
          }
        end
        
        @impl true
        def function_info(:business_days_between) do
          %{
            arity: 2,
            return_type: :integer,
            description: "Calculate business days between two dates"
          }
        end
        
        @impl true
        def function_info(:compound_interest) do
          %{
            arity: 3,
            return_type: :decimal,
            description: "Calculate compound interest"
          }
        end
      end

  Register the provider:

      RulesEngine.Engine.CalculatorRegistry.register_provider(MyApp.CustomCalculators)

  Use in DSL:

      rule "tax-calculation" do
        when
          income: Income(amount: amt, state: st)
        then
          emit TaxOwed(amount: tax_rate(st, amt))
      end
  """

  @doc """
  List all calculator functions supported by this provider.

  Returns a list of function names (atoms) that this provider can evaluate.
  Function names must be unique across all registered providers.
  """
  @callback supported_functions() :: [atom()]

  @doc """
  Evaluate a calculator function with the given arguments.

  The function name will be one of those returned by `supported_functions/0`.
  Arguments are provided as a list of already-resolved values.

  This function should:
  - Be pure (no side effects)
  - Be deterministic (same inputs produce same outputs)
  - Handle edge cases gracefully
  - Return appropriate types (typically Decimal for numeric results)

  ## Arguments
  - `function_name`: Function to execute (atom)
  - `args`: List of resolved argument values

  ## Returns
  The calculated result. Type depends on the function but should be
  consistent and documented in `function_info/1`.
  """
  @callback evaluate(function_name :: atom(), args :: [term()]) :: term()

  @doc """
  Provide metadata about a calculator function.

  Returns information about the function including arity, return type,
  and description. This is used for validation and documentation.

  ## Returns
  A map containing:
  - `:arity` - Number of expected arguments (integer)  
  - `:return_type` - Expected return type (:decimal, :integer, :string, :boolean, etc.)
  - `:description` - Human-readable description of what the function does
  """
  @callback function_info(function_name :: atom()) :: %{
              arity: non_neg_integer(),
              return_type: atom(),
              description: String.t()
            }
end
