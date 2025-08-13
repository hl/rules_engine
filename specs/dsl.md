# Rule DSL Specification (Textual DSL + IR)

A textual, Elixir-agnostic DSL compiled to a RETE IR. Author in DSL text (see `specs/dsl_ebnf.md`); engine executes compiled JSON IR (`specs/ir.schema.json`). No dynamic Elixir eval.

## Why a DSL (vs plain structs)

- Expressive domain language: Rules read as high-level intent (patterns, joins, not/exists, accumulate) instead of low-level data plumbing.
- Compile-time validation: Field names, schemas, guard purity, and deterministic constructs are checked before runtime with precise errors.
- Safety by design: Declarative constraints avoid arbitrary user code; safer for multi-tenant use within a library runtime.
- Optimizable plan: Compiler can choose alpha keys, join order, and share nodes; enables constant folding and predicate specialization for performance.
- Determinism: Enforces reproducible semantics (agenda/refraction) and disallows side effects inside conditions.
- Abstractions & reuse: Macros/helpers for common patterns reduce boilerplate and drift across large rulesets.
- Tooling & audit: Text artifacts are easy to diff, lint, document, review, and roll back with approvals.
- Cross-project portability: DSL text/AST compiles deterministically per tenant engine.
- Performance headroom: Supports partial evaluation and optional codegen of hot predicates for faster networks.
- Guardrails at scale: Consistent rule semantics across 100 tenant engines; fewer runtime surprises than ad-hoc struct encodings.
Pragmatic approach
- DSL → IR: Compile DSL to a validated internal IR/struct the engine executes.
- Escape hatches: Allow vetted predicate modules behind feature flags for rare cases.
- Strict by default: Keep the public library surface declarative; reserve imperative hooks for trusted internal code paths.

## Basics

- Rule: `rule "name" [salience: int] do ... end`
- LHS (when): `when` block with patterns and `guard ...` lines.
- RHS (then): `then` block with `emit Type(field: value, ...)` actions.
- Full grammar: `specs/dsl_ebnf.md`; examples: `specs/dsl_examples.md`.

## Namespacing and Imports

- Rules are compiled for a specific engine context and may be versioned by the host application.
- Imports: Explicit imports of calculators/helpers from whitelisted modules. No dynamic `Code.eval_string`.
- An optional `imports` block at the top of the program declares allowed functions (see EBNF).

## Patterns

- Syntax: `TypeName(field1: value_or_var, field2: value_or_var, ...)` optionally bound as `alias: TypeName(...)`.
- Bindings: Simple identifiers (e.g., `e`, `h`); constants are literals (strings, numbers, bools, dates) or enums.
- Guards: `guard <expr>` using the DSL operators (==, !=, >, >=, <, <=, in, not_in, between, and/or).
- Negation/Existence: Supported in v0 via explicit `not TypeName(...)` and `exists TypeName(...)` clauses over a single right-hand pattern. Complex negation (multi-join) is out of scope for v0.

### Examples (see `specs/dsl_examples.md` for more)

```dsl
rule "base-pay" salience: 100 do
  when
    ts: TimesheetEntry(employee_id: e, start_at: s, end_at: f, approved?: true)
    rate: PayRate(employee_id: e, rate_type: :hourly, base_rate: r)
    guard hours_between(s, f) > 0
  then
    emit PayLine(employee_id: e, period_key: bucket(:week, s), component: :base,
                 hours: hours_between(s, f), rate: r,
                 amount: r * hours_between(s, f))
end
```

## Joins

- Joins occur via shared variables (e.g., `?e` across patterns) and guard comparisons (e.g., `?x.id == ?y.customer_id`).

## Negation and Existence

- v0 supports explicit `not` and `exists` against a single pattern in the `when` block:
  - `not TypeName(field: expr, ...)` suppresses matches when any right input exists.
  - `exists TypeName(field: expr, ...)` requires at least one right input.
- Multi-pattern negation is out of scope for v0; express with precomputed facts if needed.

## Accumulation

- Syntax in `when` block (binding optional):
  - `agg: accumulate from TypeName(field: expr, ...) group_by g1, g2 reduce r1: sum(expr), r2: count(), r3: min(expr), r4: max(expr), r5: avg(expr) [having guard_expr]`
- Semantics:
  - Group key = vector of evaluated `group_by` expressions.
  - Reducers operate incrementally on asserts/modifies/retracts; avg = {sum,count}.
  - The accumulate binding exposes fields for group keys (use names of value_exprs when identifiers, else `k1..kn`) and reducer outputs by declared names.
  - `having` filters aggregates before propagation.
- Determinism and constraints:
  - Reducers must be associative/commutative, pure, and deterministic; Decimal arithmetic for numeric reducers.
  - Single `from` pattern in v0; multiple-source/windowed accumulations are out of scope.
- Errors:
  - Type mismatches produce compile-time errors where possible; runtime validation rejects invalid contributions.

## Actions

- `emit TypeName(key: val, ...)` creates a derived fact. The compiler maps DSL `TypeName` to a concrete struct or map via the schema registry (see specs/fact_schemas.md).
- `call Module.function(args...)` executes a side-effect under Engine control (use sparingly; prefer emits).
- `log level, message` records trace messages.

See specs/calculators.md for available calculators usable in guards and expressions. Calculators must be explicitly imported via an `imports` block and are pure/deterministic (no side effects, time, or I/O).

## Metadata

- `salience: integer` controls agenda priority.
- `tags: [atoms]` user-defined labels.
- `refraction: :default | :none | :custom` policy overrides.
- `group: atom` — Logical grouping for large rulesets.

## Compilation Guarantees

- Pattern ordering may be optimized; semantics preserved.
- Alpha tests reordered by selectivity; Beta joins planned left-to-right based on bound variables.
- Guards compiled to predicates executed at nodes to prune early.
