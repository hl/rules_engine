defmodule RulesEngine.Engine.PredicateRegistry do
  @moduledoc """
  Pluggable registry for predicate implementations.

  Enables host applications to register domain-specific predicates alongside
  built-in predicates. Predicates provide evaluation functions, type expectations,
  indexability hints, and selectivity estimates for query optimisation.

  ## Built-in Predicates

  The registry includes all standard predicates from `RulesEngine.Predicates`:
  - Comparison: `==`, `!=`, `>`, `>=`, `<`, `<=`
  - Collection: `in`, `not_in`, `between`, `overlap`
  - String: `starts_with`, `ends_with`, `contains`, `matches`
  - Temporal: `before`, `after`
  - Size: `size_eq`, `size_gt`
  - Approximation: `approximately`
  - Network-level: `exists`, `not_exists`

  ## Custom Predicates

  Host applications can register custom predicates by implementing the
  `RulesEngine.Engine.PredicateProvider` behaviour and registering them
  during application startup.

  ## Examples

      # Register a custom predicate provider
      PredicateRegistry.register_provider(MyApp.CustomPredicates)
      
      # Check if a predicate is supported
      PredicateRegistry.supported?(:my_custom_predicate)
      
      # Get all supported operations
      PredicateRegistry.supported_ops()
      
      # Evaluate a predicate
      PredicateRegistry.evaluate(:starts_with, "hello", "he")
      
      # Get predicate metadata
      PredicateRegistry.expectations(:before)
      PredicateRegistry.indexable?(:==)
      PredicateRegistry.selectivity_hint(:in)
  """

  use GenServer
  require Logger

  alias RulesEngine.Predicates

  @registry_name __MODULE__

  # Public API

  @doc """
  Start the predicate registry.

  Called automatically during application startup.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @registry_name)
  end

  @doc """
  Register a predicate provider module.

  Provider modules must implement the `RulesEngine.Engine.PredicateProvider` behaviour.

  ## Examples

      PredicateRegistry.register_provider(MyApp.DomainPredicates)
  """
  @spec register_provider(module()) :: :ok | {:error, term()}
  def register_provider(provider_module) do
    GenServer.call(@registry_name, {:register_provider, provider_module})
  end

  @doc """
  Unregister a predicate provider module.

  Removes all predicates provided by the given module.
  """
  @spec unregister_provider(module()) :: :ok
  def unregister_provider(provider_module) do
    GenServer.call(@registry_name, {:unregister_provider, provider_module})
  end

  @doc """
  Get all supported predicate operations.

  Returns a list of atoms representing all registered predicates.
  """
  @spec supported_ops() :: [atom()]
  def supported_ops do
    GenServer.call(@registry_name, :supported_ops)
  end

  @doc """
  Check if a predicate operation is supported.

  ## Examples

      iex> PredicateRegistry.supported?(:==)
      true
      
      iex> PredicateRegistry.supported?(:unknown)
      false
  """
  @spec supported?(atom()) :: boolean()
  def supported?(op) when is_atom(op) do
    GenServer.call(@registry_name, {:supported?, op})
  end

  @doc """
  Evaluate a predicate against two values.

  Returns boolean result of the predicate operation.
  Raises on invalid arguments or unknown predicates.

  ## Examples

      iex> PredicateRegistry.evaluate(:==, "hello", "hello")
      true
      
      iex> PredicateRegistry.evaluate(:starts_with, "hello world", "hello")
      true
  """
  @spec evaluate(atom(), term(), term()) :: boolean()
  def evaluate(op, left, right) do
    GenServer.call(@registry_name, {:evaluate, op, left, right})
  end

  @doc """
  Get type expectations for a predicate.

  Returns a map with type constraint flags used during AST validation.

  ## Examples

      iex> PredicateRegistry.expectations(:before)
      %{datetime_required?: true}
      
      iex> PredicateRegistry.expectations(:size_eq)
      %{collection_left?: true, numeric_right?: true}
  """
  @spec expectations(atom()) :: map()
  def expectations(op) when is_atom(op) do
    GenServer.call(@registry_name, {:expectations, op})
  end

  @doc """
  Check if a predicate is indexable at alpha or join nodes.

  Returns true for predicates that support efficient indexing.

  ## Examples

      iex> PredicateRegistry.indexable?(:==)
      true
      
      iex> PredicateRegistry.indexable?(:contains)
      false
  """
  @spec indexable?(atom()) :: boolean()
  def indexable?(op) when is_atom(op) do
    GenServer.call(@registry_name, {:indexable?, op})
  end

  @doc """
  Get selectivity hint for a predicate.

  Returns a float in [0.0, 1.0] where lower values indicate more selective predicates.
  Used by the query optimiser to order predicate evaluation for best performance.

  ## Examples

      iex> PredicateRegistry.selectivity_hint(:==)
      0.01
      
      iex> PredicateRegistry.selectivity_hint(:contains)
      0.3
  """
  @spec selectivity_hint(atom()) :: float()
  def selectivity_hint(op) when is_atom(op) do
    GenServer.call(@registry_name, {:selectivity_hint, op})
  end

  @doc """
  Get information about all registered predicate providers.

  Returns a list of provider modules and their provided predicates.
  """
  @spec list_providers() :: [{module(), [atom()]}]
  def list_providers do
    GenServer.call(@registry_name, :list_providers)
  end

  @doc """
  Get detailed information about a specific predicate.

  Returns metadata including provider, expectations, indexability, and selectivity.
  """
  @spec predicate_info(atom()) :: {:ok, map()} | {:error, :not_found}
  def predicate_info(op) when is_atom(op) do
    GenServer.call(@registry_name, {:predicate_info, op})
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    # Initialize with built-in predicates
    state = %{
      providers: %{},
      predicates: %{},
      built_in_ops: Predicates.supported_ops()
    }

    # Register built-in predicates
    built_in_predicates =
      Predicates.supported_ops()
      |> Enum.map(fn op ->
        {op,
         %{
           provider: Predicates,
           evaluate: &Predicates.evaluate/3,
           expectations: Predicates.expectations(op),
           indexable?: Predicates.indexable?(op),
           selectivity_hint: Predicates.selectivity_hint(op)
         }}
      end)
      |> Map.new()

    state = %{state | predicates: built_in_predicates}

    Logger.debug(
      "PredicateRegistry started with #{length(Predicates.supported_ops())} built-in predicates"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:register_provider, provider_module}, _from, state) do
    case validate_provider(provider_module) do
      {:ok, provided_ops} ->
        register_predicates(state, provider_module, provided_ops)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unregister_provider, provider_module}, _from, state) do
    case Map.get(state.providers, provider_module) do
      nil ->
        {:reply, :ok, state}

      provided_ops ->
        # Remove all predicates from this provider
        updated_predicates =
          Enum.reduce(provided_ops, state.predicates, fn op, acc ->
            Map.delete(acc, op)
          end)

        updated_state = %{
          state
          | providers: Map.delete(state.providers, provider_module),
            predicates: updated_predicates
        }

        Logger.info(
          "PredicateRegistry: Unregistered provider #{provider_module}, removed #{length(provided_ops)} predicates"
        )

        {:reply, :ok, updated_state}
    end
  end

  @impl true
  def handle_call(:supported_ops, _from, state) do
    ops = Map.keys(state.predicates)
    {:reply, ops, state}
  end

  @impl true
  def handle_call({:supported?, op}, _from, state) do
    result = Map.has_key?(state.predicates, op)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:evaluate, op, left, right}, _from, state) do
    case Map.get(state.predicates, op) do
      nil ->
        {:reply, {:error, {:unknown_predicate, op}}, state}

      predicate_info ->
        try do
          result = predicate_info.evaluate.(op, left, right)
          {:reply, result, state}
        rescue
          error ->
            {:reply, {:error, {:evaluation_failed, error}}, state}
        end
    end
  end

  @impl true
  def handle_call({:expectations, op}, _from, state) do
    case Map.get(state.predicates, op) do
      nil -> {:reply, %{}, state}
      predicate_info -> {:reply, predicate_info.expectations, state}
    end
  end

  @impl true
  def handle_call({:indexable?, op}, _from, state) do
    case Map.get(state.predicates, op) do
      nil -> {:reply, false, state}
      predicate_info -> {:reply, predicate_info.indexable?, state}
    end
  end

  @impl true
  def handle_call({:selectivity_hint, op}, _from, state) do
    case Map.get(state.predicates, op) do
      nil -> {:reply, 0.5, state}
      predicate_info -> {:reply, predicate_info.selectivity_hint, state}
    end
  end

  @impl true
  def handle_call(:list_providers, _from, state) do
    providers = Enum.map(state.providers, fn {module, ops} -> {module, ops} end)
    {:reply, providers, state}
  end

  @impl true
  def handle_call({:predicate_info, op}, _from, state) do
    case Map.get(state.predicates, op) do
      nil ->
        {:reply, {:error, :not_found}, state}

      predicate_info ->
        info = %{
          operation: op,
          provider: predicate_info.provider,
          expectations: predicate_info.expectations,
          indexable?: predicate_info.indexable?,
          selectivity_hint: predicate_info.selectivity_hint,
          built_in?: op in state.built_in_ops
        }

        {:reply, {:ok, info}, state}
    end
  end

  # Private Functions

  defp register_predicates(state, provider_module, provided_ops) do
    # Check for conflicts with existing predicates
    conflicts = Enum.filter(provided_ops, fn op -> Map.has_key?(state.predicates, op) end)

    if conflicts != [] do
      Logger.warning(
        "PredicateRegistry: Provider #{provider_module} conflicts with existing predicates: #{inspect(conflicts)}"
      )

      {:reply, {:error, {:conflicts, conflicts}}, state}
    else
      # Register all predicates from the provider
      new_predicates =
        provided_ops
        |> Enum.map(fn op ->
          {op,
           %{
             provider: provider_module,
             evaluate: &provider_module.evaluate/3,
             expectations: provider_module.expectations(op),
             indexable?: provider_module.indexable?(op),
             selectivity_hint: provider_module.selectivity_hint(op)
           }}
        end)
        |> Map.new()

      updated_state = %{
        state
        | providers: Map.put(state.providers, provider_module, provided_ops),
          predicates: Map.merge(state.predicates, new_predicates)
      }

      Logger.info(
        "PredicateRegistry: Registered provider #{provider_module} with #{length(provided_ops)} predicates: #{inspect(provided_ops)}"
      )

      {:reply, :ok, updated_state}
    end
  end

  defp validate_provider(provider_module) do
    case Code.ensure_loaded(provider_module) do
      {:module, ^provider_module} ->
        validate_provider_behaviour(provider_module)

      _ ->
        {:error, :module_not_found}
    end
  rescue
    error ->
      {:error, {:validation_error, error}}
  end

  defp validate_provider_behaviour(provider_module) do
    # Check if module implements PredicateProvider behaviour
    behaviours =
      provider_module.__info__(:attributes)
      |> Keyword.get(:behaviour, [])

    if RulesEngine.Engine.PredicateProvider in behaviours do
      validate_supported_ops(provider_module)
    else
      {:error, :missing_behaviour}
    end
  end

  defp validate_supported_ops(provider_module) do
    # Get supported operations from the provider
    provided_ops = provider_module.supported_ops()

    if is_list(provided_ops) and Enum.all?(provided_ops, &is_atom/1) do
      {:ok, provided_ops}
    else
      {:error, :invalid_supported_ops}
    end
  end
end
