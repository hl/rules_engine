import Config

# Logger configuration - define metadata keys used by RulesEngine
config :logger, :console,
  metadata: [
    :tenant_id,
    :duration_ms,
    :fires_executed,
    :agenda_size_after,
    :agenda_size,
    :working_memory_size,
    :result,
    :rules_count,
    :source_size,
    :reason,
    :policy,
    :remaining_entries,
    :max_entries,
    :max_memory_mb,
    :eviction_policy
  ]

# Configuration for RulesEngine

# Fact schema registry - configure your own schema provider in production
# config :rules_engine,
#   schema_registry: MyApp.SchemaRegistry

# Example using a module-based schema provider:
# config :rules_engine,
#   schema_registry: {MyApp.SchemaProvider, []}

# Compilation cache - enabled by default for performance
# Disable if you have memory constraints or need deterministic behavior
# config :rules_engine,
#   enable_compilation_cache: true

# For development/testing, schemas can be loaded from modules or files
