defmodule RulesEngine.Registry do
  @moduledoc """
  Registry for tenant engines and global services.

  Provides process registration and lookup for multi-tenant
  engine instances and shared services.
  """

  @doc """
  Start the registry.
  """
  def start_link(opts \\ []) do
    Registry.start_link(keys: :unique, name: __MODULE__, partitions: System.schedulers_online())
  end

  @doc """
  Child spec for supervision tree.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end
end
