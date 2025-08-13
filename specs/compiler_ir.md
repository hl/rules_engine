# Compiler IR (Intermediate Representation)

A compact, validated graph the compiler emits from the DSL for fast runtime execution and sharing.

## Goals

- Deterministic build, stable IDs for node/edge sharing
- Minimal runtime decoding; direct execution
- BSSN: only fields used now

## Core Types (skeletal)

- Network
  - version :: term
  - nodes :: %{node_id => Node}
  - edges :: [%Edge]
  - entrypoints :: [node_id]
  - metadata :: %{selectivity_hints?: boolean}
- Node (tagged union)
  - :alpha_test
    - tests :: [Predicate]    # single-WME predicates (type, attribute comparisons, ranges, set-membership)
    - out_memory :: memory_id
  - :alpha_memory
    - key :: AlphaKey
  - :join
    - left :: input_ref
    - right :: input_ref
    - on :: [JoinCond]
    - out_memory :: memory_id
  - :neg_exists
    - mode :: :not | :exists
    - left :: input_ref
    - right :: input_ref
  - :accumulate
    - from :: input_ref
    - group_by :: [Expr]
    - reducers :: [ReducerSpec]
    - out_memory :: memory_id
  - :production
    - rule_id :: String.t()
    - salience :: integer
    - refraction :: :default | :none
    - rhs :: [Action]
- Edge
  - from :: node_id
  - to :: node_id
  - bindings :: %{var => source}

## Predicates and Joins (aligned with DSL)

- Predicate
  - field :: Path.t()
  - op :: :eq | :ne | :gt | :ge | :lt | :le | :in | :not_in | :between | :overlap
  - value :: literal | var | {from :: Expr, to :: Expr}  # for :between
  - note: :overlap used for temporal window overlaps

- JoinCond
  - left :: var_or_field
  - op :: :eq                        # v0 hash-join on equality only
  - right :: var_or_field
  - post_filters :: [Predicate]       # non-equi guards evaluated after hash-join

## Memories/Indexes

- memory_id :: integer
- alpha indexes: %{AlphaKey => hash_spec}
- beta indexes: %{[vars] => hash_spec}

## Actions

- :emit, type_name :: String.t(), fields :: %{atom => Expr}
  - Mapping of DSL TypeName to concrete struct/map is performed at runtime via schema registry (see specs/fact_schemas.md).
- :call, {mod, fun, args :: [Expr]} (internal only)
- :log, level, msg :: Expr

## Reducers

- ReducerSpec
  - name :: String.t()
  - kind :: :sum | :count | :min | :max | :avg
  - expr :: Expr | nil
  - state :: opaque (implementation-defined); avg maintained as {sum, count}

## Expr (subset)

- literal | var | {op, [Expr]}

## Stability

- node_id, memory_id allocated deterministically from normalized LHS
- production_id stable per rule
- token_signature order: ordered_wme_ids follow the topologically sorted LHS (alpha-to-beta plan order), bindings hash includes only variables referenced by RHS fields

## Out of Scope (now)

- codegen modules
- advanced predicate ops beyond equality/range
- distributed links
