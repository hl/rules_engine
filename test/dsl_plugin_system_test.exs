defmodule RulesEngine.DSLPluginSystemTest do
  use ExUnit.Case, async: true
  doctest RulesEngine.DSL.PluginRegistry

  alias RulesEngine.DSL.{PluginProvider, PluginRegistry}

  # Test plugin implementation
  defmodule TestTimezonePlugin do
    @behaviour PluginProvider

    @impl true
    def plugin_name, do: :test_timezone_extensions

    @impl true
    def supported_productions do
      %{
        :value_expr => [
          {:in_timezone, "parsec(:ident) |> string(\" in timezone \") |> parsec(:string_lit)"}
        ]
      }
    end

    @impl true
    def ast_node_types do
      [
        {:in_timezone, [:datetime_binding, :timezone_string]}
      ]
    end

    @impl true
    def validate_ast_node({:in_timezone, [datetime, timezone]}, context) do
      cond do
        not is_atom(datetime) ->
          {:error, "datetime must be a binding reference"}

        not Map.has_key?(context.bindings, datetime) ->
          {:error, "unknown binding: #{datetime}"}

        not is_binary(timezone) ->
          {:error, "timezone must be string literal"}

        true ->
          :ok
      end
    end

    @impl true
    def compile_ast_node({:in_timezone, [datetime_binding, timezone]}, _context) do
      %{
        "op" => "convert_timezone",
        "left" => %{"binding" => to_string(datetime_binding), "field" => ""},
        "right" => %{"type" => "literal", "value" => timezone},
        "extra" => nil
      }
    end
  end

  # Test plugin without optional callbacks
  defmodule TestSimplePlugin do
    @behaviour PluginProvider

    @impl true
    def plugin_name, do: :test_simple_extensions

    @impl true
    def supported_productions do
      %{
        :operator => [
          {:within_miles,
           "string(\"within\") |> ignore(parsec(:ws)) |> parsec(:number) |> string(\"miles\")"}
        ]
      }
    end

    @impl true
    def ast_node_types do
      [
        {:within_miles, [:location_binding, :distance_number, :reference_location]}
      ]
    end
  end

  # Test plugin with invalid implementation
  defmodule TestInvalidPlugin do
    # Missing @behaviour and callbacks
    def plugin_name, do: :test_invalid
  end

  describe "PluginRegistry" do
    setup do
      # Registry starts automatically via supervision tree
      # Clean up any existing plugins
      for plugin <- PluginRegistry.list_plugins() do
        case Enum.find([TestTimezonePlugin, TestSimplePlugin], fn m ->
               m.plugin_name() == plugin
             end) do
          nil -> :ok
          module -> PluginRegistry.unregister_provider(module)
        end
      end

      :ok
    end

    test "register_provider validates plugin implementation" do
      assert :ok = PluginRegistry.register_provider(TestTimezonePlugin)

      # Should reject invalid plugin
      assert {:error, {:missing_callbacks, _}} =
               PluginRegistry.register_provider(TestInvalidPlugin)
    end

    test "register_provider prevents duplicate plugin names" do
      assert :ok = PluginRegistry.register_provider(TestTimezonePlugin)

      # Try to register same plugin again
      assert {:error, {:already_registered, :test_timezone_extensions}} =
               PluginRegistry.register_provider(TestTimezonePlugin)
    end

    test "list_plugins returns registered plugin names" do
      assert :ok = PluginRegistry.register_provider(TestTimezonePlugin)
      assert :ok = PluginRegistry.register_provider(TestSimplePlugin)

      plugins = PluginRegistry.list_plugins()
      assert :test_timezone_extensions in plugins
      assert :test_simple_extensions in plugins
    end

    test "get_grammar_extensions returns merged grammar extensions" do
      assert :ok = PluginRegistry.register_provider(TestTimezonePlugin)
      assert :ok = PluginRegistry.register_provider(TestSimplePlugin)

      extensions = PluginRegistry.get_grammar_extensions()

      assert Map.has_key?(extensions, :value_expr)
      assert Map.has_key?(extensions, :operator)

      assert {:in_timezone, _} = List.keyfind(extensions[:value_expr], :in_timezone, 0)
      assert {:within_miles, _} = List.keyfind(extensions[:operator], :within_miles, 0)
    end

    test "get_ast_node_types returns all node type definitions" do
      assert :ok = PluginRegistry.register_provider(TestTimezonePlugin)
      assert :ok = PluginRegistry.register_provider(TestSimplePlugin)

      node_types = PluginRegistry.get_ast_node_types()

      assert {:in_timezone, [:datetime_binding, :timezone_string]} in node_types

      assert {:within_miles, [:location_binding, :distance_number, :reference_location]} in node_types
    end

    test "unregister_provider removes plugin and rebuilds metadata" do
      assert :ok = PluginRegistry.register_provider(TestTimezonePlugin)
      assert :ok = PluginRegistry.register_provider(TestSimplePlugin)

      # Verify both are registered
      assert :test_timezone_extensions in PluginRegistry.list_plugins()
      assert :test_simple_extensions in PluginRegistry.list_plugins()

      # Unregister one
      assert :ok = PluginRegistry.unregister_provider(TestTimezonePlugin)

      # Verify it's removed
      plugins = PluginRegistry.list_plugins()
      refute :test_timezone_extensions in plugins
      assert :test_simple_extensions in plugins

      # Verify metadata is rebuilt correctly
      extensions = PluginRegistry.get_grammar_extensions()
      refute Map.has_key?(extensions, :value_expr)
      assert Map.has_key?(extensions, :operator)
    end

    test "validate_node calls appropriate plugin validation" do
      assert :ok = PluginRegistry.register_provider(TestTimezonePlugin)

      context = %{bindings: %{ts: :datetime}}

      # Valid node
      assert :ok = PluginRegistry.validate_node({:in_timezone, [:ts, "UTC"]}, context)

      # Invalid node - unknown binding
      bad_context = %{bindings: %{}}

      assert {:error, "unknown binding: ts"} =
               PluginRegistry.validate_node({:in_timezone, [:ts, "UTC"]}, bad_context)

      # Invalid node - bad timezone type
      assert {:error, "timezone must be string literal"} =
               PluginRegistry.validate_node({:in_timezone, [:ts, 123]}, context)

      # Unknown node type
      assert {:error, "no plugin handles node type: unknown_node"} =
               PluginRegistry.validate_node({:unknown_node, []}, context)
    end

    test "compile_node calls appropriate plugin compilation" do
      assert :ok = PluginRegistry.register_provider(TestTimezonePlugin)

      context = %{}

      # Valid compilation
      result = PluginRegistry.compile_node({:in_timezone, [:ts, "UTC"]}, context)

      assert %{
               "op" => "convert_timezone",
               "left" => %{"binding" => "ts", "field" => ""},
               "right" => %{"type" => "literal", "value" => "UTC"},
               "extra" => nil
             } = result

      # Unknown node type
      assert {:error, "no plugin handles node type: unknown_node"} =
               PluginRegistry.compile_node({:unknown_node, []}, context)
    end

    test "validate_node works with plugins without optional callbacks" do
      assert :ok = PluginRegistry.register_provider(TestSimplePlugin)

      context = %{bindings: %{}}

      # Should default to :ok for plugins without validate_ast_node
      assert :ok = PluginRegistry.validate_node({:within_miles, [:loc, 5, :ref]}, context)
    end

    test "compile_node works with plugins without optional callbacks" do
      assert :ok = PluginRegistry.register_provider(TestSimplePlugin)

      context = %{}

      # Should pass through unchanged for plugins without compile_ast_node
      node = {:within_miles, [:loc, 5, :ref]}
      assert ^node = PluginRegistry.compile_node(node, context)
    end
  end
end
