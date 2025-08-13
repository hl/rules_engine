# GitHub Copilot Instructions for this repository

Scope
- Language/runtime: Elixir (~> 1.19). OTP app with Mix.
- Follow AGENTS.md at repo root. Adhere to The Elixir Style Guide: https://github.com/christopheradams/elixir_style_guide and BSSN: https://dannorth.net/blog/best-simple-system-for-now/

Quality bar
- Zero tolerance for compiler warnings, failing checks, speculative “future” code, dead code, or placeholders.
- Always format (mix format) and compile with warnings as errors (mix compile --warnings-as-errors).
- Run static analysis (mix credo --strict) and Dialyzer (mix dialyzer) for non-trivial changes.

Coding guidelines
- Prefer pure, small, intention-revealing functions. Keep side effects at boundaries (Application/Supervisor trees).
- Types/specs: add @spec to all public functions; define @type t and group @typedoc/@type; place @spec directly under @doc.
- Naming: snake_case for vars/functions; PascalCase modules; predicate? booleans; ! suffix for raising variants.
- Imports/Aliases: prefer fully qualified names; alias repeated long modules; avoid import unless for macros or localising 2+ funcs.
- Errors: return {:ok, value} | {:error, reason}; raise/! only at boundaries (CLI/startup); error messages must be actionable.
- Docs: @moduledoc on modules; @doc on public APIs with runnable doctests.
- Tests: write ExUnit tests; support single-test runs (mix test path/to/file.exs:line).

Security & privacy
- Never propose committing secrets: .env, keys, tokens, credentials, or production data.
- Do not exfiltrate code or large snippets unnecessarily.

Dependencies & files
- Avoid adding dependencies without clear justification; prefer standard library or simple local code (BSSN).
- Do not generate licences/boilerplate unless explicitly requested.

Developer commands
- Build/test helpers: mix deps.get; mix format --check-formatted; mix compile --warnings-as-errors; mix credo --strict; mix dialyzer; mix test

Commit hygiene
- Write meaningful commit messages focusing on the why; keep changes minimal and cohesive.
