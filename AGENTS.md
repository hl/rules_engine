# AGENTS quickstart for this repo (Elixir Mix project)

Build/lint/test

- Install: Elixir (~> 1.19); deps: mix deps.get
- Compile: mix compile
- Format check: mix format --check-formatted
- Lint (0 warnings tolerated): mix compile --warnings-as-errors; static analysis: mix credo --strict; dialyzer: mix dialyzer
- Test all: mix test
- Test single file: mix test test/rules_engine_test.exs
- Test single test: mix test test/rules_engine_test.exs:5
- Coverage: MIX_ENV=test mix test --cover

Code style

- Formatting: mix format; follow The Elixir Style Guide (key points: parentheses in pipelines, 98-char lines, module attr ordering). Source: <https://github.com/christopheradams/elixir_style_guide>
- Imports/Aliases: prefer fully qualified names; alias repeated long modules; avoid import unless for macros or localising 2+ funcs
- Types: add @spec for public functions; prefer pattern matching over guards; define @type t and keep @typedoc/@type grouped; place specs under @doc
- Naming: snake_case for vars/functions; PascalCase modules; predicate? booleans; ! for raising variants
- Errors: return {:ok, value} | {:error, reason}; raise/! only at boundaries (CLI/startup); no crashing library code; actionable messages
- Docs: @moduledoc on modules; @doc on public functions with runnable doctests
- Logging: use Logger appropriately; avoid IO.puts in library code
- Purity/side effects: keep pure; isolate side effects in Application/Supervisor trees; remove dead/placeholder code
- Tests: ExUnit; deterministic; use setup; one behaviour per test

Practices

- BSSN (Best Simple System for Now): build only what’s needed now, to an appropriate standard. Source: <https://dannorth.net/blog/best-simple-system-for-now/>
- Zero tolerance for compiler warnings, failing checks, speculative “future” code, dead code, or placeholders
- Copilot rules: .github/copilot-instructions.md; include these constraints in reviews/generation
- CI: run format check, warnings-as-errors compile, and tests
