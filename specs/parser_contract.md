# RulesEngine DSL Parser Contract (v0)

Purpose

- Deterministically parse DSL text to a validated AST, then compile to IR conforming to `specs/ir.schema.json`.

Inputs

- tenant_id: string
- source: UTF‑8 DSL text
- options: map (optional), e.g. `%{now: DateTime.t(), max_rules: 1000}`

Outputs

- `{:ok, %Parsed{ast: ast(), rules: [rule()], warnings: [warning()], checksum: binary}}`
- `{:error, [parser_error() | validation_error()]}`

AST Shape (simplified)

- program: `[rule]`
- rule: `%{id, name, salience, bindings: [%{binding, type, fields: %{field => match_expr}}], guards: [guard_expr], actions: [action]}`
- match_expr: `literal | binding_ref | "_" | comparison | set`
- guard_expr: `comparison | set | between | logical`
- action: `%{type, fields: %{field => value_expr}}`

Determinism

- No user-defined functions. Only built‑ins: `== != > >= < <=`, `in`, `not_in`, `between`, `and`, `or`, arithmetic `+ - * /`.
- Date/time literals must use DSL tagged forms.

Validation

- Enforce identifiers (`[A-Za-z][A-Za-z0-9_]*`).
- Ensure bindings referenced in guards/actions exist.
- Ensure types and fields exist per fact schemas (see `specs/fact_schemas.md`).
- Type-check operators (e.g., `between` requires comparable types).
- Enforce limits (rule count, expr depth) to prevent pathological inputs.

Errors

- `token_error(line, col, message)`
- `syntax_error(line, col, message)`
- `validation_error(line?, col?, code, message, path)`
Examples:
- `syntax_error(5, 10, "expected ')'")`
- `validation_error(nil, nil, "unknown_field", "Timesheet.hoursx not found", "Timesheet.hoursx")`
- `validation_error(12, 5, "unknown_binding", "binding 'x' not defined", "x")`

Checksums and Versioning

- Compute SHA256 of normalised source (strip trailing spaces, normalise newlines).
- Include checksum and compiled_at in IR.

Contract Functions (Elixir)

- `parse/2`
  - Input: `source :: String.t()`, `opts :: map()`
  - Output: `{:ok, ast, warnings} | {:error, errors}`

- `compile/3`
  - Input: `tenant_id :: String.t()`, `ast`, `opts :: map()`
  - Output: `{:ok, ir_map} | {:error, errors}`
  - Must emit IR validating against `specs/ir.schema.json`.

- `parse_and_compile/3`
  - Pipeline of parse → validate → compile.

Error Handling

- Return tuples; never raise on user input.
- Include best‑effort locations for validation errors tied to bindings/fields.

Security

- Treat DSL as data. Never eval as Elixir.
- Reject excessive size/depth via limits.

Testing

- Golden tests: source → AST → IR; verify schema validation, checksums, and stable output.
