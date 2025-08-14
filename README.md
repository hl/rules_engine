# RulesEngine

A pragmatic, test-first rules engine for Elixir. Author domain rules in a small DSL, parse and validate them, and compile to a typed intermediate representation (IR). The runtime engine is WIP; today you can parse and compile the DSL to IR and use it for static analysis and downstream execution.

- Parse a human-friendly DSL into an AST
- Validate bindings, predicates, and field access against schemas
- Compile to a stable IR JSON (see specs/ and test fixtures)
- Planned: alpha/beta network runtime with agenda and refraction

## Quick start

```bash
# Get deps and compile
mix deps.get
mix compile

# Run tests (parsing + IR conformance)
mix test
```

### Parse a DSL file to IR

```elixir
# In IEx
{:ok, dsl} = File.read!("test/fixtures/dsl/ruleset_basic.rule") |> RulesEngine.DSL.Parser.parse()
{:ok, ast} = RulesEngine.DSL.Compiler.ast(dsl)
{:ok, ir}  = RulesEngine.compile(ast)

# ir is a map you can encode to JSON
Jason.encode!(ir)
```

See `test/fixtures/dsl/*.rule` alongside expected JSON in `test/fixtures/json/*.json`.

## Installation

This project isn’t published to Hex yet. For now, depend via Git in `mix.exs`:

```elixir
{:rules_engine, git: "https://github.com/<your-org>/rules_engine", tag: "v0.0.0"}
```

## DSL overview

- Facts and patterns; guards with boolean/set/temporal predicates
- Support for and/or groupings; not/exists and accumulate are planned
- See specs for the grammar and examples:
  - specs/dsl.md, specs/dsl_ebnf.md, specs/dsl_examples.md
  - specs/accumulation.md, specs/temporal_semantics.md

## Development

- Style: mix format; credo --strict; no warnings in CI
- Run full suite: `mix test` (see CI workflow in .github/workflows/ci.yml)
- Key entry points:
  - RulesEngine.DSL.Parser – parse DSL to AST
  - RulesEngine.DSL.Validate – validate AST
  - RulesEngine.DSL.Compiler – AST to IR
  - RulesEngine.Predicates – predicate expectations

## Roadmap

Tracked in TODO.md. Immediate focus: complete DSL coverage, improve validation, attach rich error diagnostics, and harden IR compilation ahead of the runtime engine.

## License

TBD – see TODO.md; will add SPDX license in a follow-up.
