defmodule RulesEngine.DSL.Plugins.ExampleTimezonePlugin do
  @moduledoc """
  Example DSL plugin demonstrating timezone syntax extensions.

  This plugin adds timezone conversion syntax to the DSL, allowing rules
  to express timezone-aware datetime comparisons. It showcases:

  - Custom grammar productions
  - AST node type definitions  
  - Validation logic for custom syntax
  - Compilation to standard IR components

  ## Usage

  Register the plugin during application startup:

      RulesEngine.DSL.PluginRegistry.register_provider(
        RulesEngine.DSL.Plugins.ExampleTimezonePlugin
      )

  Then use the extended syntax in rules:

      rule "timezone-aware-rule" do
        when
          event: Event(timestamp: ts)
          guard ts in timezone "America/New_York" > ~N[2024-01-01 18:00:00]
        then
          emit Alert(message: "After hours event detected")
      end

  The `in timezone` expression converts the datetime binding to the specified
  timezone before comparison, enabling timezone-aware business rules.

  ## Implementation Notes

  - The grammar extension injects into `:value_expr` production
  - Validation ensures referenced bindings exist and timezones are strings
  - Compilation transforms to `convert_timezone` function calls in IR
  - Compatible with existing datetime predicates and operations
  """

  @behaviour RulesEngine.DSL.PluginProvider

  @impl true
  def plugin_name, do: :timezone_extensions

  @impl true
  def supported_productions do
    %{
      # Add timezone conversion syntax to value expressions
      :value_expr => [
        {:in_timezone, "parsec(:ident) |> string(\" in timezone \") |> parsec(:string_lit)"}
      ]
    }
  end

  @impl true
  def ast_node_types do
    [
      # Define AST structure: {node_type, [field_names]}
      {:in_timezone, [:datetime_binding, :timezone_string]}
    ]
  end

  @impl true
  def validate_ast_node({:in_timezone, [datetime, timezone]}, context) do
    cond do
      not is_atom(datetime) ->
        {:error, "datetime must be a binding reference, got: #{inspect(datetime)}"}

      not Map.has_key?(context.bindings, datetime) ->
        {:error, "unknown binding: #{datetime}"}

      not is_binary(timezone) ->
        {:error, "timezone must be a string literal, got: #{inspect(timezone)}"}

      not valid_timezone?(timezone) ->
        {:error, "invalid timezone: #{timezone}"}

      true ->
        :ok
    end
  end

  @impl true
  def compile_ast_node({:in_timezone, [datetime_binding, timezone]}, _context) do
    # Transform to function call in IR - compatible with existing guard format
    %{
      "op" => "convert_timezone",
      "left" => %{"binding" => to_string(datetime_binding), "field" => ""},
      "right" => %{"type" => "literal", "value" => timezone},
      "extra" => nil
    }
  end

  # Private helper - basic timezone validation
  defp valid_timezone?(timezone) when is_binary(timezone) do
    # Simple validation - in production this could use a timezone library
    case timezone do
      "UTC" ->
        true

      "GMT" ->
        true

      tz when is_binary(tz) ->
        # Basic format check for IANA timezone names
        String.match?(tz, ~r|^[A-Za-z]+/[A-Za-z_]+$|)

      _invalid_timezone ->
        false
    end
  end
end
