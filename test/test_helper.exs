ExUnit.start()

# Start the application for tests so ETS tables are created
{:ok, _} = Application.ensure_all_started(:rules_engine)

# Force load test support modules - the elixirc_paths may not work in all test scenarios
Code.ensure_loaded!(RulesEngineTest.Support.FactSchemas)
Code.ensure_loaded!(RulesEngineTest.Support.TestCalculators)

# Register test calculator providers
case RulesEngine.Engine.CalculatorRegistry.register_provider(
       RulesEngineTest.Support.TestCalculators
     ) do
  :ok ->
    :ok

  {:error, reason} ->
    IO.puts("Warning: Failed to register test calculators: #{inspect(reason)}")
end
