import Config

# Configuration for test environment
# Use test-specific fact schemas for validation testing
config :rules_engine,
  schema_registry: RulesEngineTest.Support.FactSchemas
