defmodule RulesEngine.Engine.CalculatorRegistry do
  @moduledoc """
  Registry for calculator functions used in DSL expressions.

  This GenServer maintains a registry of both built-in calculator functions
  from RulesEngine.Calculators and custom calculator functions provided by
  host applications via CalculatorProvider implementations.

  ## Built-in Calculators

  The following functions are automatically registered from RulesEngine.Calculators:
  - time_between/3 - Calculate time between DateTimes
  - overlap_hours/4 - Calculate overlapping hours between time periods
  - bucket/2, bucket/3 - Group DateTime into period buckets
  - decimal_add/2, decimal_subtract/2, decimal_multiply/2 - Decimal arithmetic
  - dec/1 - Create Decimal from string literal

  ## Custom Calculators

  Host applications can register additional calculator functions:

      defmodule MyApp.CustomCalculators do
        @behaviour RulesEngine.Engine.CalculatorProvider
        
        @impl true
        def supported_functions, do: [:tax_rate, :business_days]
        
        @impl true  
        def evaluate(:tax_rate, [state, income]), do: calculate_tax(state, income)
        def evaluate(:business_days, [start_date, end_date]), do: count_business_days(start_date, end_date)
        
        @impl true
        def function_info(:tax_rate), do: %{arity: 2, return_type: :decimal, description: "Calculate tax"}
        def function_info(:business_days), do: %{arity: 2, return_type: :integer, description: "Count business days"}
      end

      # Register the provider
      CalculatorRegistry.register_provider(MyApp.CustomCalculators)

  ## Validation Integration

  The registry integrates with DSL validation to ensure function calls use:
  - Known function names
  - Correct argument counts
  - Appropriate types
  """

  use GenServer
  require Logger

  alias RulesEngine.Calculators

  @typedoc "Calculator function metadata"
  @type function_info :: %{
          arity: non_neg_integer(),
          return_type: atom(),
          description: String.t(),
          provider: module()
        }

  @typedoc "Registry state"
  @type state :: %{
          functions: %{atom() => function_info()},
          providers: %{module() => [atom()]}
        }

  # Client API

  @doc "Start the calculator registry"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Register a calculator provider"
  @spec register_provider(module()) :: :ok | {:error, term()}
  def register_provider(provider_module) do
    GenServer.call(__MODULE__, {:register_provider, provider_module})
  end

  @doc "Unregister a calculator provider"
  @spec unregister_provider(module()) :: :ok
  def unregister_provider(provider_module) do
    GenServer.call(__MODULE__, {:unregister_provider, provider_module})
  end

  @doc "Check if a function is supported"
  @spec supported?(atom()) :: boolean()
  def supported?(function_name) do
    GenServer.call(__MODULE__, {:supported?, function_name})
  end

  @doc "Get function information"
  @spec function_info(atom()) :: {:ok, function_info()} | {:error, :not_found}
  def function_info(function_name) do
    GenServer.call(__MODULE__, {:function_info, function_name})
  end

  @doc "List all supported functions"
  @spec list_functions() :: [atom()]
  def list_functions do
    GenServer.call(__MODULE__, :list_functions)
  end

  @doc "Evaluate a calculator function"
  @spec evaluate(atom(), [term()]) :: {:ok, term()} | {:error, term()}
  def evaluate(function_name, args) do
    GenServer.call(__MODULE__, {:evaluate, function_name, args})
  end

  @doc "Get all registered providers"
  @spec list_providers() :: [module()]
  def list_providers do
    GenServer.call(__MODULE__, :list_providers)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{
      functions: %{},
      providers: %{}
    }

    # Register built-in calculators automatically
    {:ok, state} = register_builtin_calculators(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:register_provider, provider_module}, _from, state) do
    case validate_provider_behaviour(provider_module) do
      :ok ->
        case register_provider_functions(state, provider_module) do
          {:ok, new_state} ->
            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unregister_provider, provider_module}, _from, state) do
    new_state = unregister_provider_functions(state, provider_module)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:supported?, function_name}, _from, state) do
    supported = Map.has_key?(state.functions, function_name)
    {:reply, supported, state}
  end

  @impl true
  def handle_call({:function_info, function_name}, _from, state) do
    case Map.get(state.functions, function_name) do
      nil -> {:reply, {:error, :not_found}, state}
      info -> {:reply, {:ok, info}, state}
    end
  end

  @impl true
  def handle_call(:list_functions, _from, state) do
    functions = Map.keys(state.functions)
    {:reply, functions, state}
  end

  @impl true
  def handle_call({:evaluate, function_name, args}, _from, state) do
    case Map.get(state.functions, function_name) do
      nil ->
        {:reply, {:error, {:unknown_function, function_name}}, state}

      %{provider: provider_module} ->
        try do
          result =
            if provider_module == Calculators do
              # Handle built-in calculators with direct function calls
              apply(provider_module, function_name, args)
            else
              # Use the evaluate callback for custom providers
              provider_module.evaluate(function_name, args)
            end

          {:reply, {:ok, result}, state}
        rescue
          e ->
            {:reply, {:error, {:evaluation_error, e}}, state}
        end
    end
  end

  @impl true
  def handle_call(:list_providers, _from, state) do
    providers = Map.keys(state.providers)
    {:reply, providers, state}
  end

  # Private functions

  defp register_builtin_calculators(state) do
    builtin_functions = %{
      time_between: %{
        arity: 3,
        return_type: :decimal,
        description: "Calculate time between two DateTimes in specified units",
        provider: RulesEngine.Calculators
      },
      overlap_hours: %{
        arity: 4,
        return_type: :decimal,
        description: "Calculate overlapping hours between two time periods",
        provider: RulesEngine.Calculators
      },
      bucket: %{
        arity: 2,
        return_type: :tuple,
        description: "Group DateTime into period buckets",
        provider: RulesEngine.Calculators
      },
      decimal_add: %{
        arity: 2,
        return_type: :decimal,
        description: "Add two Decimal values",
        provider: RulesEngine.Calculators
      },
      decimal_subtract: %{
        arity: 2,
        return_type: :decimal,
        description: "Subtract two Decimal values",
        provider: RulesEngine.Calculators
      },
      decimal_multiply: %{
        arity: 2,
        return_type: :decimal,
        description: "Multiply two Decimal values",
        provider: RulesEngine.Calculators
      },
      dec: %{
        arity: 1,
        return_type: :decimal,
        description: "Create a Decimal from string literal",
        provider: RulesEngine.Calculators
      }
    }

    new_state = %{
      state
      | functions: Map.merge(state.functions, builtin_functions),
        providers: Map.put(state.providers, RulesEngine.Calculators, Map.keys(builtin_functions))
    }

    {:ok, new_state}
  end

  defp validate_provider_behaviour(provider_module) do
    required_functions = [
      {:supported_functions, 0},
      {:evaluate, 2},
      {:function_info, 1}
    ]

    missing =
      required_functions
      |> Enum.reject(fn {fun, arity} ->
        function_exported?(provider_module, fun, arity)
      end)

    case missing do
      [] -> :ok
      _ -> {:error, {:missing_callbacks, missing}}
    end
  end

  defp register_provider_functions(state, provider_module) do
    provided_functions = provider_module.supported_functions()

    # Check for conflicts with existing functions
    conflicts =
      Enum.filter(provided_functions, fn func ->
        Map.has_key?(state.functions, func)
      end)

    case conflicts do
      [] ->
        validate_and_register_functions(state, provider_module, provided_functions)

      _ ->
        {:error, {:conflicts, conflicts}}
    end
  rescue
    e ->
      {:error, {:provider_error, e}}
  end

  defp validate_and_register_functions(state, provider_module, provided_functions) do
    function_infos =
      provided_functions
      |> Map.new(fn func ->
        info = provider_module.function_info(func)
        enhanced_info = Map.put(info, :provider, provider_module)
        {func, enhanced_info}
      end)

    new_state = %{
      state
      | functions: Map.merge(state.functions, function_infos),
        providers: Map.put(state.providers, provider_module, provided_functions)
    }

    Logger.info(
      "Registered calculator provider #{provider_module} with functions: #{inspect(provided_functions)}"
    )

    {:ok, new_state}
  rescue
    e ->
      {:error, {:function_info_error, e}}
  end

  defp unregister_provider_functions(state, provider_module) do
    case Map.get(state.providers, provider_module) do
      nil ->
        state

      provided_functions ->
        new_functions =
          provided_functions
          |> Enum.reduce(state.functions, fn func, acc ->
            Map.delete(acc, func)
          end)

        new_providers = Map.delete(state.providers, provider_module)

        Logger.info("Unregistered calculator provider #{provider_module}")

        %{state | functions: new_functions, providers: new_providers}
    end
  end
end
