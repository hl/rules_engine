# Fact Schemas — External Schema Configuration

This document defines how to configure fact schemas for the rules engine. Schemas define the allowed fields for fact types and enable validation during DSL compilation. The rules engine library itself is domain-agnostic and requires external schema configuration.

## Configuration

### Application Configuration

Configure a schema registry in your application config:

```elixir
# config/config.exs
config :rules_engine,
  schema_registry: MyApp.SchemaRegistry

# Or with options:
config :rules_engine,
  schema_registry: {MyApp.SchemaProvider, []}
```

### Schema Provider Requirements

Schema providers must implement a `schemas/0` function returning a map:

```elixir
defmodule MyApp.SchemaRegistry do
  def schemas do
    %{
      "Employee" => %{"fields" => ["id", "name", "role", "location"]},
      "PayLine" => %{"fields" => ["employee_id", "amount", "hours"]}
    }
  end
end
```

### Using Schemas During Compilation

Pass schemas explicitly during DSL compilation:

```elixir
# Using configured registry
schemas = RulesEngine.SchemaRegistry.schemas()
{:ok, ir} = RulesEngine.DSL.Compiler.compile_dsl(source, %{fact_schemas: schemas})

# Disable validation
{:ok, ir} = RulesEngine.DSL.Compiler.compile_dsl(source, %{fact_schemas: nil})
```

## LLM Integration

The schema registry provides functions for external tools and LLMs:

```elixir
# List all available fact types
RulesEngine.SchemaRegistry.list_schemas()
# => ["Employee", "PayLine", "TimesheetEntry"]

# Get detailed schema information
RulesEngine.SchemaRegistry.schema_details()
# => [
#   %{fact_type: "Employee", fields: ["id", "name", "role"], field_count: 3},
#   %{fact_type: "PayLine", fields: ["employee_id", "amount"], field_count: 2}
# ]
```

## Schema Format Conventions

- IDs: `id` is a stable string or integer. Referential fields end with `_id`.
- Time: Normalise instants to UTC `DateTime` at ingest; `Date` for all-day items; effective windows use `[effective_from, effective_to)` (to is exclusive).
- Keys: Discriminating keys used by Alpha indexes include `type`, `employee_id`, `location`, dates, and scenario identifiers.
- Precision: Monetary amounts use `Decimal`. DSL literals use `dec("12.34")` helper or numbers interpreted as Decimal by the compiler where unambiguous.
- Structs: Example Elixir structs shown for clarity; maps with equivalent keys are also accepted.

## Example Schema Definitions

The following are example schemas for common payroll/compliance domains. Applications should define their own schemas based on their specific requirements:

### Core WMEs (Working Memory Elements)

```elixir
%{
  "Employee" => %{
    "fields" => ["id", "role", "location", "union", "employment_type", "effective_from", "effective_to"]
  },
  "TimesheetEntry" => %{
    "fields" => ["id", "employee_id", "start_at", "end_at", "hours", "project_id", "cost_center", "approved?"]
  },
  "PayRate" => %{
    "fields" => ["id", "employee_id", "role", "rate_type", "base_rate", "effective_from", "effective_to"]
  },
  "OvertimePolicy" => %{
    "fields" => ["id", "jurisdiction", "union", "threshold_hours", "multiplier", "period", "effective_from", "effective_to"]
  }
}
```

### Derived Facts

```elixir
%{
  "PayLine" => %{
    "fields" => ["employee_id", "period_key", "component", "hours", "rate", "amount", "provenance"]
  },
  "ComplianceViolation" => %{
    "fields" => ["employee_id", "period_key", "code", "severity", "details", "provenance"]
  }
}
```

### Example Usage in Application

```elixir
defmodule MyApp.PayrollSchemas do
  def schemas do
    %{
      "Employee" => %{"fields" => ["id", "name", "role", "department"]},
      "Timesheet" => %{"fields" => ["id", "employee_id", "hours", "date"]},
      "PayLine" => %{"fields" => ["employee_id", "amount", "pay_date"]}
    }
  end
end

# In your config
config :rules_engine, schema_registry: MyApp.PayrollSchemas
```

Note: These example schemas define field names for validation purposes. The runtime engine will process facts as maps or structs with these field names, normalizing inputs before matching (e.g., compute derived fields if missing).
