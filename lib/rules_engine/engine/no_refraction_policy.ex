defmodule RulesEngine.Engine.NoRefractionPolicy do
  @moduledoc """
  No refraction policy - allows rules to fire repeatedly.

  Disables refraction entirely, allowing rules to fire multiple times
  on the same data. Useful for scenarios where repeated firing is desired
  or when refraction overhead should be avoided.
  """

  @behaviour RulesEngine.Engine.RefractionPolicy

  alias RulesEngine.Engine.Activation

  @doc """
  Always return :allow to bypass refraction.
  """
  @impl true
  def refraction_key(%Activation{}), do: :allow

  @doc """
  Always allow firing, never refract.
  """
  @impl true
  def should_refract(%Activation{}, store, _opts) do
    {:fire, store}
  end

  @doc """
  Create minimal store (empty tuple since nothing is stored).
  """
  @impl true
  def init_store(_opts), do: {}

  @doc """
  Get policy name for debugging.
  """
  @impl true
  def name, do: "no_refraction"

  @doc """
  Get policy description.
  """
  @impl true
  def description do
    "Disables refraction - allows unlimited rule re-firing on same data"
  end
end
