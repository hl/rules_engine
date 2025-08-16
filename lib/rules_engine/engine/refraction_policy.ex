defmodule RulesEngine.Engine.RefractionPolicy do
  @moduledoc """
  Behaviour for custom refraction policies.

  Refraction policies determine how to prevent rules from firing repeatedly
  on the same data. Different policies support varying levels of
  granularity and memory efficiency.
  """

  alias RulesEngine.Engine.Activation

  @doc """
  Generate a refraction key for an activation.

  The refraction key should uniquely identify a rule firing context.
  If two activations generate the same key, the second one will be
  suppressed (refracted).

  Returns the key to store in the refraction store, or `:allow`
  to bypass refraction entirely for this activation.
  """
  @callback refraction_key(activation :: Activation.t()) :: term() | :allow

  @doc """
  Check if an activation should be refracted based on the store.

  ## Parameters
  - `activation` - The activation being evaluated
  - `store` - Current refraction store state
  - `opts` - Policy-specific options

  Returns `{:refract, store}` to suppress the activation,
  or `{:fire, new_store}` to allow it and update the store.
  """
  @callback should_refract(activation :: Activation.t(), store :: term(), opts :: keyword()) ::
              {:refract, term()} | {:fire, term()}

  @doc """
  Create initial refraction store state.

  Returns the initial state for the refraction store.
  """
  @callback init_store(opts :: keyword()) :: term()

  @doc """
  Clean expired entries from refraction store.

  Called periodically to remove old refraction entries.
  Returns updated store state.
  """
  @callback cleanup_store(store :: term(), opts :: keyword()) :: term()

  @doc """
  Get the policy name for debugging and logging.
  """
  @callback name() :: String.t()

  @doc """
  Get a human-readable description of the policy.
  """
  @callback description() :: String.t()

  @optional_callbacks [name: 0, description: 0, cleanup_store: 2]
end
