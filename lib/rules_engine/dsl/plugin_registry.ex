defmodule RulesEngine.DSL.PluginRegistry do
  @moduledoc """
  Registry for DSL syntax extension plugins.

  Manages registration and discovery of DSL plugins that extend the parser
  grammar with custom syntax, AST nodes, and compilation behaviors.

  ## Plugin Discovery

  The registry automatically discovers and validates plugins on startup.
  Plugins must implement the `RulesEngine.DSL.PluginProvider` behaviour
  and register themselves during application startup.

  ## Grammar Integration

  When the parser starts, it queries the registry for all grammar extensions
  and dynamically builds the extended parser with custom productions injected
  at the appropriate extension points.

  ## Thread Safety

  The registry is implemented as a GenServer to ensure thread-safe access
  to plugin metadata during concurrent parsing operations.

  ## Examples

      # Register a plugin during application startup
      PluginRegistry.register_provider(MyApp.TimeZonePlugin)
      
      # Check available plugins
      PluginRegistry.list_plugins()
      #=> [:timezone_extensions, :financial_calculations]
      
      # Get all grammar extensions
      PluginRegistry.get_grammar_extensions()
      #=> %{
      #     value_expr: [{:in_timezone, "parsec(:ident) |> string(\" in timezone \") |> parsec(:string_lit)"}],
      #     operator: [{:within_miles, "string(\"within\") |> parsec(:number) |> string(\"miles\")"}]
      #   }
      
      # Validate custom AST node
      context = %{bindings: %{ts: :datetime}}
      PluginRegistry.validate_node({:in_timezone, [:ts, "UTC"]}, context)
      #=> :ok
      
      # Compile custom AST node
      PluginRegistry.compile_node({:in_timezone, [:ts, "UTC"]}, %{})
      #=> %{type: :function_call, function: :convert_timezone, ...}
  """

  use GenServer
  require Logger

  @type plugin_name :: atom()
  @type production_name :: atom()
  @type grammar_extension :: {atom(), String.t()}
  @type grammar_extensions :: %{production_name() => [grammar_extension()]}

  # Client API

  @doc """
  Start the plugin registry.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a DSL plugin provider.

  The provider must implement the `RulesEngine.DSL.PluginProvider` behaviour.
  Registration validates the plugin and stores its metadata for use during
  parsing and compilation.

  ## Examples

      PluginRegistry.register_provider(MyApp.TimeZonePlugin)
      #=> :ok
  """
  @spec register_provider(module()) :: :ok | {:error, term()}
  def register_provider(provider_module) when is_atom(provider_module) do
    GenServer.call(__MODULE__, {:register_provider, provider_module})
  end

  @doc """
  Unregister a DSL plugin provider.

  Removes the plugin from the registry. This operation requires a parser
  restart to take effect since grammar extensions are compiled at startup.
  """
  @spec unregister_provider(module()) :: :ok
  def unregister_provider(provider_module) when is_atom(provider_module) do
    GenServer.call(__MODULE__, {:unregister_provider, provider_module})
  end

  @doc """
  List all registered plugin names.
  """
  @spec list_plugins() :: [plugin_name()]
  def list_plugins do
    GenServer.call(__MODULE__, :list_plugins)
  end

  @doc """
  Get all grammar extensions from registered plugins.

  Returns a map of production names to lists of grammar extensions.
  Used by the parser to build the extended grammar at startup.
  """
  @spec get_grammar_extensions() :: grammar_extensions()
  def get_grammar_extensions do
    GenServer.call(__MODULE__, :get_grammar_extensions)
  end

  @doc """
  Get all custom AST node type definitions.

  Returns a list of `{node_type, field_names}` tuples from all plugins.
  """
  @spec get_ast_node_types() :: [{atom(), [atom()]}]
  def get_ast_node_types do
    GenServer.call(__MODULE__, :get_ast_node_types)
  end

  @doc """
  Validate a custom AST node using the appropriate plugin.

  Finds the plugin that handles the given node type and calls its
  validation function. Returns `:ok` if valid or `{:error, reason}` if not.
  """
  @spec validate_node(term(), map()) :: :ok | {:error, String.t()}
  def validate_node(ast_node, context) do
    GenServer.call(__MODULE__, {:validate_node, ast_node, context})
  end

  @doc """
  Compile a custom AST node using the appropriate plugin.

  Finds the plugin that handles the given node type and calls its
  compilation function. Returns the compiled IR node.
  """
  @spec compile_node(term(), map()) :: map()
  def compile_node(ast_node, context) do
    GenServer.call(__MODULE__, {:compile_node, ast_node, context})
  end

  # GenServer Callbacks

  @impl GenServer
  def init(_opts) do
    Logger.debug("DSL PluginRegistry started")
    {:ok, %{providers: %{}, extensions: %{}, node_types: []}}
  end

  @impl GenServer
  def handle_call({:register_provider, provider_module}, _from, state) do
    case validate_provider(provider_module) do
      :ok ->
        plugin_name = provider_module.plugin_name()

        if Map.has_key?(state.providers, plugin_name) do
          {:reply, {:error, {:already_registered, plugin_name}}, state}
        else
          extensions = merge_extensions(state.extensions, provider_module.supported_productions())
          node_types = state.node_types ++ provider_module.ast_node_types()

          new_state = %{
            state
            | providers: Map.put(state.providers, plugin_name, provider_module),
              extensions: extensions,
              node_types: node_types
          }

          Logger.info("Registered DSL plugin: #{plugin_name}")
          {:reply, :ok, new_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:unregister_provider, provider_module}, _from, state) do
    plugin_name =
      if function_exported?(provider_module, :plugin_name, 0) do
        provider_module.plugin_name()
      else
        nil
      end

    if plugin_name && Map.has_key?(state.providers, plugin_name) do
      # Remove provider and rebuild extensions/types from remaining providers
      remaining_providers = Map.delete(state.providers, plugin_name)
      {extensions, node_types} = rebuild_metadata(remaining_providers)

      new_state = %{
        state
        | providers: remaining_providers,
          extensions: extensions,
          node_types: node_types
      }

      Logger.info("Unregistered DSL plugin: #{plugin_name}")
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_call(:list_plugins, _from, state) do
    plugin_names = Map.keys(state.providers)
    {:reply, plugin_names, state}
  end

  @impl GenServer
  def handle_call(:get_grammar_extensions, _from, state) do
    {:reply, state.extensions, state}
  end

  @impl GenServer
  def handle_call(:get_ast_node_types, _from, state) do
    {:reply, state.node_types, state}
  end

  @impl GenServer
  def handle_call({:validate_node, ast_node, context}, _from, state) do
    node_type = extract_node_type(ast_node)

    case find_provider_for_node(node_type, state.providers) do
      {:ok, provider} ->
        if function_exported?(provider, :validate_ast_node, 2) do
          result = provider.validate_ast_node(ast_node, context)
          {:reply, result, state}
        else
          {:reply, :ok, state}
        end

      :not_found ->
        {:reply, {:error, "no plugin handles node type: #{node_type}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:compile_node, ast_node, context}, _from, state) do
    node_type = extract_node_type(ast_node)

    case find_provider_for_node(node_type, state.providers) do
      {:ok, provider} ->
        if function_exported?(provider, :compile_ast_node, 2) do
          result = provider.compile_ast_node(ast_node, context)
          {:reply, result, state}
        else
          # Default: pass through unchanged
          {:reply, ast_node, state}
        end

      :not_found ->
        {:reply, {:error, "no plugin handles node type: #{node_type}"}, state}
    end
  end

  # Private Helpers

  defp validate_provider(provider_module) do
    required_functions = [:plugin_name, :supported_productions, :ast_node_types]

    missing =
      Enum.filter(required_functions, fn func ->
        not function_exported?(provider_module, func, 0)
      end)

    if missing == [] do
      :ok
    else
      {:error, {:missing_callbacks, missing}}
    end
  end

  defp merge_extensions(current_extensions, new_extensions) do
    Map.merge(current_extensions, new_extensions, fn _key, existing, new ->
      existing ++ new
    end)
  end

  defp rebuild_metadata(providers) when providers == %{}, do: {%{}, []}

  defp rebuild_metadata(providers) do
    extensions =
      providers
      |> Map.values()
      |> Enum.reduce(%{}, fn provider, acc ->
        merge_extensions(acc, provider.supported_productions())
      end)

    node_types =
      providers
      |> Map.values()
      |> Enum.flat_map(& &1.ast_node_types())

    {extensions, node_types}
  end

  defp extract_node_type({node_type, _fields}) when is_atom(node_type), do: node_type
  defp extract_node_type(node_type) when is_atom(node_type), do: node_type
  defp extract_node_type(_), do: :unknown

  defp find_provider_for_node(node_type, providers) do
    Enum.find_value(providers, :not_found, fn {_name, provider} ->
      node_types = provider.ast_node_types() |> Enum.map(&elem(&1, 0))

      if node_type in node_types do
        {:ok, provider}
      else
        nil
      end
    end)
  end
end
