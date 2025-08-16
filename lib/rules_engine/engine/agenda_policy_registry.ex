defmodule RulesEngine.Engine.AgendaPolicyRegistry do
  @moduledoc """
  Registry of built-in agenda policies with discovery and configuration helpers.

  Provides standardised access to agenda policies for host applications.
  """

  alias RulesEngine.Engine.{
    AgendaPolicy,
    DefaultAgendaPolicy,
    FifoAgendaPolicy,
    LifoAgendaPolicy,
    SalienceOnlyAgendaPolicy
  }

  @built_in_policies [
    {:default, DefaultAgendaPolicy},
    {:fifo, FifoAgendaPolicy},
    {:lifo, LifoAgendaPolicy},
    {:salience_only, SalienceOnlyAgendaPolicy}
  ]

  @doc """
  Get all available agenda policies.

  Returns a list of {name, module} tuples for all built-in policies.
  """
  @spec list_policies() :: [{atom(), module()}]
  def list_policies do
    @built_in_policies
  end

  @doc """
  Resolve agenda policy from atom or module.

  ## Examples

      iex> resolve_policy(:default)
      {:ok, RulesEngine.Engine.DefaultAgendaPolicy}

      iex> resolve_policy(MyCustomPolicy)
      {:ok, MyCustomPolicy}

      iex> resolve_policy(:unknown)
      {:error, :unknown_policy}
  """
  @spec resolve_policy(atom() | module()) :: {:ok, module()} | {:error, :unknown_policy}
  def resolve_policy(policy) when is_atom(policy) do
    case Keyword.get(@built_in_policies, policy) do
      nil when policy in [nil, :default] ->
        {:ok, DefaultAgendaPolicy}

      nil ->
        # Check if it's a module implementing the behaviour
        if implements_agenda_policy?(policy) do
          {:ok, policy}
        else
          {:error, :unknown_policy}
        end

      module ->
        {:ok, module}
    end
  end

  def resolve_policy(_), do: {:error, :unknown_policy}

  @doc """
  Get policy information including name and description.

  Returns metadata for a given policy module.

  ## Examples

      iex> policy_info(RulesEngine.Engine.DefaultAgendaPolicy)
      {:ok, %{name: "default_salience_recency_specificity", description: "Orders by salience..."}}
  """
  @spec policy_info(module()) :: {:ok, map()} | {:error, :invalid_policy}
  def policy_info(policy_module) when is_atom(policy_module) do
    if implements_agenda_policy?(policy_module) do
      name =
        if function_exported?(policy_module, :name, 0), do: policy_module.name(), else: "unknown"

      description =
        if function_exported?(policy_module, :description, 0),
          do: policy_module.description(),
          else: "No description available"

      {:ok, %{name: name, description: description, module: policy_module}}
    else
      {:error, :invalid_policy}
    end
  end

  def policy_info(_), do: {:error, :invalid_policy}

  @doc """
  Get information for all registered policies.

  Returns a list of policy metadata maps.
  """
  @spec list_policy_info() :: [map()]
  def list_policy_info do
    @built_in_policies
    |> Enum.map(fn {_name, module} -> policy_info(module) end)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, info} -> info end)
  end

  # Private functions

  defp implements_agenda_policy?(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        module.__info__(:attributes)
        |> Keyword.get(:behaviour, [])
        |> Enum.member?(AgendaPolicy)

      _ ->
        false
    end
  rescue
    _ -> false
  end
end
