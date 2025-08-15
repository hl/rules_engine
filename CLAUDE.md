# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RulesEngine is a RETE-based rules engine library for Elixir that parses domain-specific language (DSL) rules and compiles them to intermediate representation (IR). It's designed for business rules in domains like payroll, compliance, and cost estimation.

**Architecture**: DSL → AST → Validation → IR compilation. Runtime engine is work-in-progress.

**Key Components**:
- `RulesEngine.DSL.Parser` - NimbleParsec-based DSL parser
- `RulesEngine.DSL.Compiler` - AST to IR compiler 
- `RulesEngine.DSL.Validate` - AST validation against schemas
- `RulesEngine.Predicates` - predicate expectations and evaluation

## Development Commands

### Core Commands
```bash
# Install dependencies
mix deps.get

# Compile with zero warnings policy
mix compile --warnings-as-errors

# Format code (required)
mix format

# Format check for CI
mix format --check-formatted

# Run all tests
mix test

# Run single test file
mix test test/rules_engine_test.exs

# Run single test
mix test test/rules_engine_test.exs:5

# Coverage report
MIX_ENV=test mix test --cover
```

### Quality Checks
```bash
# Static analysis (strict)
mix credo --strict

# Type analysis
mix dialyzer
```

## Code Architecture

### DSL Processing Pipeline
1. **Parser** (`parser.ex`): DSL text → AST using NimbleParsec
2. **Validator** (`validate.ex`): AST validation against fact schemas and predicate expectations
3. **Compiler** (`compiler.ex`): AST → IR with alpha/beta network generation

### Key Data Flow
- Input: DSL files (`.rule` extension in `test/fixtures/dsl/`)
- Output: JSON IR (examples in `test/fixtures/json/`)
- Validation: Against fact schemas and predicate type expectations

### Important Patterns
- **Error Handling**: Use `{:ok, result} | {:error, reason}` tuples
- **AST Structure**: Normalised when/then tuples with salience as integers
- **IR Format**: Conforms to `specs/ir.schema.json`
- **Fact Patterns**: Support bindings, guards, and complex predicates

## Testing Strategy

- **Fixtures**: DSL files in `test/fixtures/dsl/` with expected JSON in `test/fixtures/json/`
- **Coverage**: End-to-end DSL parsing and IR conformance tests
- **Validation Tests**: Error surfaces for unknown bindings, invalid operands
- **Property Tests**: For parser round-trip idempotence (planned)

Key test files:
- `dsl_to_ir_e2e_test.exs` - Full pipeline tests
- `validation_*_test.exs` - Validation error handling
- `spec_examples_coverage_test.exs` - Spec conformance

## DSL Examples

Basic rule structure:
```elixir
rule "overtime-check" salience: 50 do
  when
    entry: TimesheetEntry(employee_id: e, hours: h)
    policy: OvertimePolicy(threshold_hours: t)
    guard h > t
  then
    emit PayLine(employee_id: e, component: :overtime, hours: h - t)
end
```

## Code Style Enforcement

- **Zero warnings** tolerance - use `--warnings-as-errors`
- **Format**: Always run `mix format` before commits
- **Specs**: `@spec` required for all public functions
- **Docs**: `@moduledoc` and `@doc` with doctests where applicable
- **Naming**: `snake_case` functions, `PascalCase` modules, `predicate?` booleans

## Common Tasks

### Adding New DSL Features
1. Update grammar in `parser.ex` (NimbleParsec combinators)
2. Add AST node types and validation in `validate.ex`
3. Implement IR compilation in `compiler.ex`
4. Add test fixtures: DSL → expected JSON
5. Update predicate expectations if needed

### Working with Specifications
- Comprehensive specs in `specs/` directory
- Key files: `dsl.md`, `compiler_ir.md`, `rete_overview.md`
- IR schema: `specs/ir.schema.json`

### Domain Context
- **Payroll**: Overtime rules, wage calculations, premiums
- **Compliance**: Break violations, rest period checks
- **Cost Estimation**: Labor cost projections

## Important Notes

- This is a library (no Phoenix/gRPC) - focus on clean APIs
- Multi-tenant design - rules compiled per tenant
- RETE algorithm implementation in progress
- Deterministic evaluation with salience-based agenda
- Comprehensive error reporting with source location info