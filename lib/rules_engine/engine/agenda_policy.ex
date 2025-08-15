defmodule RulesEngine.Engine.AgendaPolicy do
  @moduledoc """
  Behaviour for custom agenda ordering policies.

  Allows pluggable conflict resolution strategies for rule activation
  ordering. Implementations can prioritize by salience, recency,
  specificity, or custom business logic.
  """

  alias RulesEngine.Engine.Activation

  @doc """
  Compare two activations for priority ordering.

  Should return true if activation1 should fire before activation2.
  Must provide total ordering for deterministic behaviour.
  """
  @callback compare(activation1 :: Activation.t(), activation2 :: Activation.t()) :: boolean()

  @doc """
  Get the policy name for debugging and logging.
  """
  @callback name() :: String.t()

  @doc """
  Get a human-readable description of the policy.
  """
  @callback description() :: String.t()

  @optional_callbacks [name: 0, description: 0]
end
