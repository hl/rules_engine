defmodule RulesEngine.SchemaRegistry do
  @moduledoc """
  Schema registry for external fact schema configuration.

  This module provides the interface for accessing and managing fact schemas 
  in the rules engine. Schemas define the allowed fields for fact types and
  enable validation during DSL compilation.

  ## Configuration

  Configure a schema registry in your application config:

      config :rules_engine,
        schema_registry: MyApp.SchemaProvider

  Or with options:

      config :rules_engine,
        schema_registry: {MyApp.SchemaProvider, []}

  ## Schema Provider Requirements

  Schema providers must implement a `schemas/0` function that returns a map
  where keys are fact type names (strings) and values are schema definitions:

      %{
        "Employee" => %{"fields" => ["id", "name", "role"]},
        "PayLine" => %{"fields" => ["employee_id", "amount", "hours"]}
      }
  """

  @doc """
  Get all available schemas from the configured schema registry.
  Returns an empty map if no schema registry is configured.
  """
  @spec schemas() :: map()
  def schemas do
    case Application.get_env(:rules_engine, :schema_registry) do
      nil ->
        %{}

      {module, _opts} ->
        module.schemas()

      module when is_atom(module) ->
        module.schemas()

      _ ->
        %{}
    end
  end

  @doc """
  Get schema for a specific fact type.
  Returns nil if the type is not found.
  """
  @spec get_schema(String.t()) :: map() | nil
  def get_schema(fact_type) when is_binary(fact_type) do
    Map.get(schemas(), fact_type)
  end

  @doc """
  Get allowed fields for a specific fact type.
  Returns empty list if the type is not found.
  """
  @spec get_fields(String.t()) :: [String.t()]
  def get_fields(fact_type) when is_binary(fact_type) do
    case get_schema(fact_type) do
      %{"fields" => fields} -> fields
      _ -> []
    end
  end

  @doc """
  Check if a field is allowed for a given fact type.
  """
  @spec field_allowed?(String.t(), String.t()) :: boolean()
  def field_allowed?(fact_type, field_name) when is_binary(fact_type) and is_binary(field_name) do
    field_name in get_fields(fact_type)
  end

  @doc """
  List all available fact schema names.
  Useful for LLM integration and external tooling.
  """
  @spec list_schemas() :: [String.t()]
  def list_schemas do
    schemas()
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Get detailed information about all schemas in a format suitable for LLM consumption.
  Returns a list of maps with schema details.
  """
  @spec schema_details() :: [map()]
  def schema_details do
    schemas()
    |> Enum.map(fn {fact_type, schema} ->
      fields = Map.get(schema, "fields", [])

      %{
        fact_type: fact_type,
        fields: fields,
        field_count: length(fields)
      }
    end)
    |> Enum.sort_by(& &1.fact_type)
  end
end
