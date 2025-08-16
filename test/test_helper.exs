ExUnit.start()

# Ensure test support modules are loaded
Code.require_file("support/fact_schemas.ex", __DIR__)

# Start the application for tests so ETS tables are created
{:ok, _} = Application.ensure_all_started(:rules_engine)
