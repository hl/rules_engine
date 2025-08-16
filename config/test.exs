import Config

# Configuration for test environment
# Use test-specific fact schemas for validation testing
# Disable compilation cache in tests for deterministic behavior
config :rules_engine,
  schema_registry: RulesEngineTest.Support.FactSchemas,
  enable_compilation_cache: false
