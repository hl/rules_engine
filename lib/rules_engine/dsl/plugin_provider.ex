defmodule RulesEngine.DSL.PluginProvider do
  @moduledoc """
  Behaviour for implementing custom DSL syntax extensions.

  Host applications can implement this behaviour to add domain-specific 
  syntax to the RulesEngine DSL. Plugins can extend grammar productions,
  define custom AST node types, and handle compilation of custom syntax.

  ## Overview

  The plugin system allows extending the DSL parser with:
  - **Grammar Extensions**: New syntax patterns and productions
  - **Custom AST Nodes**: Domain-specific AST node types  
  - **Compilation Hooks**: Transform custom nodes during IR compilation
  - **Validation Extensions**: Validate custom syntax during AST validation

  ## Example Implementation

      defmodule MyApp.TimeZonePlugin do
        @behaviour RulesEngine.DSL.PluginProvider
        
        @impl true
        def plugin_name, do: :timezone_extensions
        
        @impl true
        def supported_productions do
          %{
            # Add 'in_timezone' expression to value expressions
            :value_expr => [
              {:in_timezone, ~S|parsec(:ident) |> string(" in timezone ") |> parsec(:string_lit)|}
            ]
          }
        end
        
        @impl true
        def ast_node_types do
          [
            {:in_timezone, [:datetime_value, :timezone_name]}
          ]
        end
        
        @impl true
        def validate_ast_node({:in_timezone, [datetime, timezone]}, _context) do
          cond do
            not is_atom(datetime) -> {:error, "datetime must be a binding reference"}
            not is_binary(timezone) -> {:error, "timezone must be a string literal"}  
            true -> :ok
          end
        end
        
        @impl true
        def compile_ast_node({:in_timezone, [datetime_binding, timezone]}, context) do
          # Transform to function call in IR
          %{
            type: :function_call,
            function: :convert_timezone,
            args: [
              %{type: :binding_ref, name: datetime_binding},
              %{type: :literal, value: timezone}
            ]
          }
        end
      end

  Register during application startup:

      RulesEngine.DSL.PluginRegistry.register_provider(MyApp.TimeZonePlugin)

  Then use in DSL:

      rule "timezone-check" do
        when 
          event: Event(timestamp: ts)
          guard ts in timezone "America/New_York" > some_threshold
        then
          emit Alert(message: "Late event detected")
      end

  ## Grammar Extension Format

  Grammar extensions use NimbleParsec combinator syntax as strings.
  The plugin system will parse and inject these into the main grammar.

  Common extension patterns:
  - **New operators**: `{:custom_op, ~S|string("custom_op")|}` 
  - **New expressions**: `{:special_expr, ~S|parsec(:ident) |> string("->") |> parsec(:value)|}`
  - **New statement types**: `{:custom_stmt, ~S|string("special") |> parsec(:block)|}`

  ## Compilation Integration

  Custom AST nodes are processed during IR compilation through the
  `compile_ast_node/2` callback. This allows transforming custom syntax
  into standard IR components or injecting custom compilation logic.

  ## Limitations

  - Grammar extensions must not conflict with core DSL syntax
  - Custom nodes must compile to valid IR components
  - Plugin registration is static at application startup
  - Grammar precedence follows plugin registration order
  """

  @doc """
  Return unique plugin name for identification and conflict detection.

  Must return an atom that uniquely identifies this plugin.
  Plugin names must be unique across all registered providers.

  ## Examples

      def plugin_name, do: :timezone_extensions
      def plugin_name, do: :financial_calculations  
  """
  @callback plugin_name() :: atom()

  @doc """
  Return grammar productions to extend in the DSL parser.

  Returns a map where keys are production names (atoms) and values are lists
  of `{tag, combinator_string}` tuples. The combinator strings use
  NimbleParsec syntax and will be injected into the specified productions.

  ## Production Extension Points

  - `:value_expr` - Extend value expressions (literals, bindings, function calls)
  - `:operator` - Add new operators for guards and comparisons
  - `:statement` - Add new top-level statement types
  - `:fact_pattern` - Extend fact pattern matching syntax
  - `:action` - Add new action types in 'then' blocks

  ## Examples

      def supported_productions do
        %{
          :value_expr => [
            {:in_timezone, ~S|parsec(:ident) |> string(" in timezone ") |> parsec(:string_lit)|}
          ],
          :operator => [
            {:within_miles, ~S|string("within") |> ignore(parsec(:ws)) |> parsec(:number) |> string("miles")|}
          ]
        }
      end
  """
  @callback supported_productions() :: %{atom() => [{atom(), String.t()}]}

  @doc """
  Return custom AST node type definitions.

  Returns a list of `{node_type, field_names}` tuples defining the structure
  of custom AST nodes. Field names should be atoms representing the expected
  child elements in order.

  These definitions are used for AST validation and provide structure
  information for the compilation process.

  ## Examples

      def ast_node_types do
        [
          {:in_timezone, [:datetime_binding, :timezone_string]},
          {:within_miles, [:location_binding, :distance_number, :reference_location]}
        ]
      end
  """
  @callback ast_node_types() :: [{atom(), [atom()]}]

  @doc """
  Validate a custom AST node during AST validation phase.

  Called for each custom AST node during DSL validation to check:
  - Node structure matches expected format
  - Field types and values are valid
  - Referenced bindings exist in context
  - Custom domain constraints are satisfied

  Return `:ok` if valid, or `{:error, reason}` if validation fails.

  ## Arguments

  - `ast_node` - The custom AST node to validate  
  - `context` - Validation context with available bindings and metadata

  ## Examples

      def validate_ast_node({:in_timezone, [datetime, timezone]}, context) do
        cond do
          not Map.has_key?(context.bindings, datetime) -> 
            {:error, "unknown binding: \#{datetime}"}
          not is_binary(timezone) -> 
            {:error, "timezone must be string literal"}
          true -> 
            :ok
        end
      end
  """
  @callback validate_ast_node(ast_node :: term(), context :: map()) ::
              :ok | {:error, String.t()}

  @doc """
  Compile custom AST node to standard IR representation.

  Called during IR compilation to transform custom AST nodes into
  standard IR components. Must return valid IR node structure that
  conforms to the IR schema.

  Custom nodes typically compile to:
  - Function calls for custom operations
  - Predicate comparisons for custom operators  
  - Standard IR nodes with custom metadata

  ## Arguments

  - `ast_node` - The custom AST node to compile
  - `context` - Compilation context with bindings, metadata, and IR state

  ## Examples

      def compile_ast_node({:in_timezone, [datetime, timezone]}, _context) do
        %{
          type: :function_call,
          function: :convert_timezone,
          args: [
            %{type: :binding_ref, name: datetime},
            %{type: :literal, value: timezone}
          ]
        }
      end
  """
  @callback compile_ast_node(ast_node :: term(), context :: map()) :: map()

  @optional_callbacks [
    validate_ast_node: 2,
    compile_ast_node: 2
  ]
end
