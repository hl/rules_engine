defmodule RulesEngine.Engine.PerRuleRefractionPolicy do
  @moduledoc """
  Per-rule refraction policy.

  Prevents a rule from firing more than once per session, regardless
  of different token combinations. More aggressive than default policy.
  Useful for rules that should only execute once (e.g., initialization, notifications).
  """

  @behaviour RulesEngine.Engine.RefractionPolicy

  alias RulesEngine.Engine.Activation

  @doc """
  Generate refraction key based only on production ID.
  """
  @impl true
  def refraction_key(%Activation{} = activation) do
    activation.production_id
  end

  @doc """
  Check if rule has already fired using rule-based lookup.
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
  def name, do: "per_rule"

  @doc """
  Get policy description.
  """
  @impl true
  def description do
    "Prevents rule from firing more than once per session (rule-level refraction)"
  end
end
