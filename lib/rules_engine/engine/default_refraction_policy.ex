defmodule RulesEngine.Engine.DefaultRefractionPolicy do
  @moduledoc """
  Default refraction policy using exact per-activation signatures.

  Prevents a rule from firing multiple times with the same token
  combination by storing activation signatures in a MapSet.
  This is the classic RETE refraction behaviour.
  """

  @behaviour RulesEngine.Engine.RefractionPolicy

  alias RulesEngine.Engine.Activation

  @doc """
  Generate refraction key based on production ID and token signature.
  """
  @impl true
  def refraction_key(%Activation{} = activation) do
    Activation.refraction_key(activation)
  end

  @doc """
  Check if activation should be refracted using MapSet lookup.
  """
  @impl true
  def should_refract(%Activation{} = activation, store, _opts) do
    key = refraction_key(activation)

    if MapSet.member?(store, key) do
      {:refract, store}
    else
      {:fire, MapSet.put(store, key)}
    end
  end

  @doc """
  Create initial MapSet store.
  """
  @impl true
  def init_store(_opts) do
    MapSet.new()
  end

  @doc """
  Get policy name for debugging.
  """
  @impl true
  def name, do: "default_per_activation"

  @doc """
  Get policy description.
  """
  @impl true
  def description do
    "Prevents rule from firing on identical token combinations (classic RETE refraction)"
  end
end
