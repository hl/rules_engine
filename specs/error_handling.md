# Error Handling

Defines validation, runtime error policy, and side-effect handling.

## Input Validation

- Strict mode: Reject facts missing required fields with `{:error, {:invalid_fact, reason}}`.
- Lenient mode: Accept but mark facts with `:invalid` tag; rules can ignore or surface issues.
- Normalization: Compute derived fields (e.g., `hours`) if absent and determinable.

## RHS Failures

- Actions run within Engine boundaries. On exception:
  - Retry policy: `:none` (default), `{:exponential, attempts, base_ms}`.
  - Dead letter: Emit `EngineError` derived fact with context and stack for operators.
  - Isolation: Failures do not corrupt WM; batch continues unless configured otherwise.

## Idempotency

- Re-submitting identical deltas is idempotent. Engine detects duplicates via fact `id` and content hash.

## Batch Semantics

- A batch of deltas is processed atomically with respect to agenda snapshots. Partial failures roll back the batch (configurable).
