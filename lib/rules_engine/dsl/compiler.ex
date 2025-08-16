defmodule RulesEngine.DSL.Compiler do
  @moduledoc """
  Parse and compile DSL to IR per specs/ir.schema.json.

  ## Compilation Caching

  The compiler includes an intelligent caching system to avoid recompiling
  unchanged DSL sources. Caching is enabled by default and can be controlled
  via application configuration:

      # Enable/disable compilation cache (default: true)
      config :rules_engine, enable_compilation_cache: true

  Cache behavior can also be controlled per-compilation via the `:cache` option
  passed to `parse_and_compile/3`.

  ## Release Compatibility

  This module is fully compatible with Mix releases and does not depend on
  Mix being available at runtime.
  """
  alias RulesEngine.DSL.{Parser, PluginRegistry, Validate}
  alias RulesEngine.Engine.PredicateRegistry

  @doc """
  Parse only.
  """
  @spec parse(String.t(), map()) :: {:ok, any(), [any()]} | {:error, [any()]}
  def parse(source, _opts \\ %{}), do: Parser.parse(source)

  @doc """
  Compile AST to IR per ir.schema.json.
  Options: now: DateTime.t(), tenant_id: required, checksum?: true
  """
  @spec compile(String.t(), any(), map()) :: {:ok, map()} | {:error, [any()]}
  def compile(tenant_id, ast, opts \\ %{}) when is_binary(tenant_id) do
    with {:ok, rules} <- compile_rules(ast),
         {:ok, ir} <- build_ir(tenant_id, rules, opts),
         :ok <- validate_ir_schema(ir) do
      {:ok, ir}
    end
  end

  @doc """
  Full pipeline: parse then compile. Computes checksum of normalised source.
  """
  @spec parse_and_compile(String.t(), String.t(), map()) :: {:ok, map()} | {:error, [any()]}
  def parse_and_compile(tenant_id, source, opts \\ %{}) do
    start_time = System.monotonic_time()
    checksum = Base.encode16(:crypto.hash(:sha256, normalise_source(source)), case: :lower)

    :telemetry.execute([:rules_engine, :compile, :start], %{}, %{
      tenant_id: tenant_id,
      source_size: byte_size(source),
      checksum: checksum
    })

    # Check cache first if caching is enabled (default: true, can be disabled via config)
    default_cache = Application.get_env(:rules_engine, :enable_compilation_cache, true)
    cache_enabled = Map.get(opts, :cache, default_cache)

    result =
      case cache_enabled do
        true ->
          case RulesEngine.CompilationCache.get(checksum, tenant_id) do
            {:hit, ir} ->
              {:ok, ir}

            :miss ->
              compile_from_source(tenant_id, source, checksum, opts, cache_enabled)
          end

        false ->
          compile_from_source(tenant_id, source, checksum, opts, cache_enabled)
      end

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, ir} ->
        :telemetry.execute([:rules_engine, :compile, :stop], %{duration: duration}, %{
          tenant_id: tenant_id,
          source_size: byte_size(source),
          result: :success,
          rules_count: length(Map.get(ir, "rules", [])),
          cache_hit: cache_enabled
        })

      {:error, errors} ->
        :telemetry.execute([:rules_engine, :compile, :stop], %{duration: duration}, %{
          tenant_id: tenant_id,
          source_size: byte_size(source),
          result: :error,
          error_count: length(errors)
        })
    end

    result
  end

  defp compile_from_source(tenant_id, source, checksum, opts, cache_enabled) do
    with {:ok, ast, _warn} <- parse(source, opts),
         {:ok, _ast} <- Validate.validate(ast, opts) do
      # Include original source for source mapping
      compile_opts =
        opts
        |> Map.put(:source_checksum, checksum)
        |> Map.put(:original_source, source)

      case compile(tenant_id, ast, compile_opts) do
        {:ok, ir} = result ->
          # Cache the result if caching is enabled

          if cache_enabled do
            RulesEngine.CompilationCache.put(checksum, tenant_id, ir)
          end

          result

        error ->
          error
      end
    end
  end

  defp normalise_source(source) do
    source
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> Enum.map_join("\n", &String.trim_trailing/1)
  end

  defp compile_rules(ast) when is_list(ast) do
    rules = Enum.map(ast, &compile_rule/1)
    {:ok, rules}
  end

  defp build_ir(tenant_id, rules, opts) do
    now = DateTime.to_iso8601(Map.get(opts, :now, DateTime.utc_now()))

    # Clean internal fields from rules before including in final IR
    clean_rules = Enum.map(rules, &clean_internal_fields/1)

    {:ok,
     %{
       "version" => "v1",
       "tenant_id" => tenant_id,
       "source_checksum" => Map.get(opts, :source_checksum),
       "compiled_at" => now,
       "rules" => clean_rules,
       "network" => %{
         "alpha" => build_alpha_network(rules),
         "beta" => build_beta_network(rules),
         "accumulate" => build_accumulate_nodes(rules),
         "agenda" => []
       },
       "agenda_policy" => build_agenda_policy(rules),
       "refraction_policy" => build_refraction_policy(rules),
       "source_map" => build_source_map(rules, opts)
     }}
  end

  # Remove internal fields used during compilation but not needed in final IR
  defp clean_internal_fields(rule) do
    Map.drop(rule, ["_accumulates"])
  end

  defp build_alpha_network(rules) do
    # Optimized O(n log n) alpha network construction
    # Step 1: Build sorted fact type index - O(n log n)
    fact_type_index = build_fact_type_index(rules)

    # Step 2: Extract and group patterns efficiently - O(n)
    {fact_patterns, not_exists_patterns} = extract_patterns_batch(rules)

    # Step 3: Build alpha nodes with batch processing - O(n log n)
    alpha_nodes_from_facts = build_alpha_nodes_batch(fact_patterns, fact_type_index)
    alpha_nodes_from_not_exists = build_alpha_nodes_batch(not_exists_patterns, fact_type_index)

    # Step 4: Efficient deduplication using Map - O(n)
    merge_and_deduplicate_alpha_nodes(alpha_nodes_from_facts, alpha_nodes_from_not_exists)
  end

  defp build_beta_network(rules) do
    # Optimized O(n log n) beta network construction
    # Step 1: Pre-compute binding reference index - O(n)
    binding_index = build_binding_reference_index(rules)

    # Step 2: Build join nodes with optimized algorithms - O(n log n)
    join_nodes = build_join_nodes_optimized(rules, binding_index)
    not_exists_nodes = build_not_exists_nodes_optimized(rules, binding_index)

    join_nodes ++ not_exists_nodes
  end

  defp build_accumulate_nodes(rules) do
    # Extract accumulate statements from rules and build accumulate network nodes
    rules
    |> Enum.with_index()
    |> Enum.flat_map(fn {rule, rule_idx} ->
      build_accumulate_nodes_for_rule(rule, rule_idx)
    end)
  end

  defp build_agenda_policy(rules) do
    # Build agenda policy configuration based on rules and specifications
    rule_metadata = build_rule_metadata(rules)

    %{
      "policy" => "default",
      "ordering" => [
        %{"criterion" => "salience", "direction" => "desc"},
        %{"criterion" => "recency", "direction" => "lifo"},
        %{"criterion" => "specificity", "direction" => "desc"},
        %{"criterion" => "rule_id", "direction" => "asc"}
      ],
      "configuration" => %{
        "max_queue" => :infinity,
        "fire_limit" => :infinity
      },
      "rules" => rule_metadata
    }
  end

  defp build_rule_metadata(rules) do
    # Calculate rule specificity and other metadata for agenda ordering
    Enum.map(rules, fn rule ->
      specificity = calculate_rule_specificity(rule)

      %{
        "rule_id" => rule["id"],
        "salience" => rule["salience"],
        "specificity" => specificity,
        # Use rule_id for deterministic tiebreaking
        "deterministic_order" => rule["id"]
      }
    end)
  end

  defp calculate_rule_specificity(rule) do
    # Calculate specificity based on:
    # - Number of bindings (fact patterns)
    # - Number of guards/conditions
    # - Depth in network (more conditions = higher specificity)

    binding_count = length(rule["bindings"] || [])
    join_count = length(rule["beta_joins"] || [])
    accumulate_count = length(rule["_accumulates"] || [])

    # Higher numbers = more specific rules
    binding_count + join_count + accumulate_count * 2
  end

  defp build_refraction_policy(rules) do
    # Build refraction policy configuration based on specs/refraction.md
    rule_refraction = build_rule_refraction_settings(rules)

    %{
      "default_policy" => "per_production",
      "signature_components" => ["production_id", "ordered_wme_ids", "binding_hash"],
      "storage" => %{
        "backend" => "ets_per_production",
        "default_ttl" => "24h",
        "max_signatures_per_rule" => :infinity,
        "eviction_policy" => "ttl_then_lru"
      },
      "scope_options" => %{
        "per_production" => %{
          "description" => "Separate refraction set per rule",
          "isolation" => true
        },
        "global" => %{
          "description" => "Shared refraction across rule families",
          "isolation" => false
        }
      },
      "rules" => rule_refraction
    }
  end

  defp build_rule_refraction_settings(rules) do
    # For each rule, determine refraction settings
    # Currently defaulting since parser doesn't support refraction metadata yet
    Enum.map(rules, fn rule ->
      %{
        "rule_id" => rule["id"],
        # Future: could be :none, :custom
        "policy" => "default",
        # Future: rule-specific TTL override
        "ttl" => "24h",
        "scope" => "per_production",
        "custom_signature_module" => nil,
        # Token signature calculation metadata
        "signature_data" => %{
          "production_id" => rule["id"],
          "binding_count" => length(rule["bindings"] || []),
          "deterministic_order" => true
        }
      }
    end)
  end

  defp build_source_map(rules, opts) do
    # Build source map for traceability between IR and original DSL source
    original_source = Map.get(opts, :original_source, "")

    if original_source == "" do
      # No source available, return minimal source map
      %{
        "version" => 1,
        "source_available" => false,
        "mappings" => []
      }
    else
      # Build detailed source map
      %{
        "version" => 1,
        "source_available" => true,
        "source_length" => byte_size(original_source),
        "line_count" => length(String.split(original_source, "\n")),
        "mappings" => build_rule_mappings(rules, original_source)
      }
    end
  end

  defp build_rule_mappings(rules, source) do
    # Map each rule to its source location by analyzing the source text
    lines = String.split(source, "\n", trim: false)

    Enum.map(rules, fn rule ->
      rule_name = rule["id"]
      # Find the line containing this rule declaration
      rule_line = find_rule_line(lines, rule_name)

      %{
        "rule_id" => rule_name,
        "source_location" => %{
          "start_line" => rule_line,
          "end_line" => find_rule_end_line(lines, rule_line),
          "start_column" => 1,
          "byte_offset" => calculate_byte_offset(lines, rule_line)
        },
        "components" => build_component_mappings(rule, lines, rule_line)
      }
    end)
  end

  defp find_rule_line(lines, rule_name) do
    # Find the line number (1-based) where this rule is declared
    Enum.find_index(lines, fn line ->
      String.contains?(line, "rule \"#{rule_name}\"") or
        String.contains?(line, "rule '#{rule_name}'")
    end)
    |> case do
      # Fallback if not found
      nil -> 1
      # Convert to 1-based indexing
      idx -> idx + 1
    end
  end

  defp find_rule_end_line(lines, start_line) do
    # Find the corresponding 'end' for this rule
    end_line =
      Enum.find_index(Enum.drop(lines, start_line - 1), fn line ->
        String.trim(line) == "end"
      end)

    case end_line do
      # Fallback
      nil -> start_line
      offset -> start_line + offset
    end
  end

  defp calculate_byte_offset(lines, target_line) do
    # Calculate byte offset to the start of target_line
    lines
    |> Enum.take(target_line - 1)
    # +1 for newline
    |> Enum.map(fn line -> byte_size(line) + 1 end)
    |> Enum.sum()
  end

  defp build_component_mappings(rule, lines, rule_line) do
    # Map rule components (when, then, actions) to source locations
    %{
      "when_clause" => find_when_location(lines, rule_line),
      "then_clause" => find_then_location(lines, rule_line),
      "bindings" => map_bindings_to_source(rule["bindings"] || [], lines, rule_line),
      "actions" => map_actions_to_source(rule["actions"] || [], lines, rule_line)
    }
  end

  defp find_when_location(lines, rule_line) do
    # Find 'when' keyword location relative to rule start
    when_line =
      Enum.find_index(Enum.drop(lines, rule_line - 1), fn line ->
        String.trim(line) == "when"
      end)

    case when_line do
      nil -> %{"line" => rule_line, "column" => 1}
      offset -> %{"line" => rule_line + offset, "column" => 3}
    end
  end

  defp find_then_location(lines, rule_line) do
    # Find 'then' keyword location
    then_line =
      Enum.find_index(Enum.drop(lines, rule_line - 1), fn line ->
        String.trim(line) == "then"
      end)

    case then_line do
      nil -> %{"line" => rule_line, "column" => 1}
      offset -> %{"line" => rule_line + offset, "column" => 3}
    end
  end

  defp map_bindings_to_source(bindings, _lines, rule_line) do
    # For now, provide approximate locations for bindings
    # In a full implementation, this would parse the when clause in detail
    Enum.with_index(bindings)
    |> Enum.map(fn {binding, idx} ->
      %{
        "binding_name" => binding["binding"],
        "fact_type" => binding["type"],
        # Rough estimate
        "estimated_line" => rule_line + 3 + idx,
        "estimated_column" => 5
      }
    end)
  end

  defp map_actions_to_source(actions, _lines, rule_line) do
    # Provide approximate locations for actions
    Enum.with_index(actions)
    |> Enum.map(fn {action, idx} ->
      %{
        "action_type" => action["op"],
        # Rough estimate after 'then'
        "estimated_line" => rule_line + 6 + idx,
        "estimated_column" => 5
      }
    end)
  end

  defp validate_ir_schema(ir) do
    # Load schema
    schema_path = Path.expand("../../../specs/ir.schema.json", __DIR__)
    schema = schema_path |> File.read!() |> Jason.decode!()
    {:ok, root} = JSV.build(schema)

    # Step 1: Direct validation of original IR
    with :ok <- validate_ir_direct(ir, root),
         # Step 2: Round-trip cast and validate for schema hardening
         :ok <- validate_ir_round_trip(ir, root) do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  defp validate_ir_direct(ir, schema_root) do
    case JSV.validate(ir, schema_root) do
      {:ok, _} ->
        :ok

      {:error, errors} ->
        {:error,
         [
           %{
             code: :schema_validation_failed,
             stage: :direct_validation,
             errors: errors
           }
         ]}
    end
  end

  defp validate_ir_round_trip(ir, schema_root) do
    # Perform round-trip JSON serialization to catch schema issues that only
    # appear after real-world serialization/deserialization cycles
    # Step 1: Serialize to JSON (as would happen in real usage)
    json_string = Jason.encode!(ir)

    # Step 2: Deserialize back to Elixir data (as would happen when loading)
    round_tripped_ir = Jason.decode!(json_string)

    # Step 3: Validate the round-tripped version
    case JSV.validate(round_tripped_ir, schema_root) do
      {:ok, _} ->
        # Step 4: Check for any significant data changes in round-trip
        check_round_trip_integrity(ir, round_tripped_ir)

      {:error, errors} ->
        {:error,
         [
           %{
             code: :schema_validation_failed,
             stage: :round_trip_validation,
             message: "IR failed validation after JSON round-trip serialization",
             errors: errors
           }
         ]}
    end
  rescue
    error in Jason.EncodeError ->
      {:error,
       [
         %{
           code: :json_serialization_failed,
           stage: :round_trip_encoding,
           message: "IR contains data that cannot be serialized to JSON",
           details: Exception.message(error)
         }
       ]}

    error in Jason.DecodeError ->
      {:error,
       [
         %{
           code: :json_deserialization_failed,
           stage: :round_trip_decoding,
           message: "Serialized IR cannot be deserialized from JSON",
           details: Exception.message(error)
         }
       ]}
  end

  defp check_round_trip_integrity(original, round_tripped) do
    # Check for critical data that might be lost or corrupted in round-trip
    issues = []

    issues = check_rule_count_integrity(original, round_tripped, issues)
    issues = check_network_integrity(original, round_tripped, issues)
    issues = check_critical_fields_integrity(original, round_tripped, issues)

    case issues do
      [] ->
        :ok

      errors ->
        {:error,
         [
           %{
             code: :round_trip_integrity_failed,
             stage: :integrity_check,
             message: "Data integrity issues detected after JSON round-trip",
             issues: errors
           }
         ]}
    end
  end

  defp check_rule_count_integrity(original, round_tripped, issues) do
    orig_count = length(original["rules"] || [])
    rt_count = length(round_tripped["rules"] || [])

    if orig_count != rt_count do
      [%{type: :rule_count_mismatch, original: orig_count, round_tripped: rt_count} | issues]
    else
      issues
    end
  end

  defp check_network_integrity(original, round_tripped, issues) do
    orig_network = original["network"] || %{}
    rt_network = round_tripped["network"] || %{}

    network_issues =
      [
        check_network_component_count(orig_network, rt_network, "alpha"),
        check_network_component_count(orig_network, rt_network, "beta"),
        check_network_component_count(orig_network, rt_network, "accumulate")
      ]
      |> Enum.filter(& &1)

    issues ++ network_issues
  end

  defp check_network_component_count(orig_network, rt_network, component) do
    orig_count = length(orig_network[component] || [])
    rt_count = length(rt_network[component] || [])

    if orig_count != rt_count do
      %{
        type: :network_component_count_mismatch,
        component: component,
        original: orig_count,
        round_tripped: rt_count
      }
    else
      nil
    end
  end

  defp check_critical_fields_integrity(original, round_tripped, issues) do
    # Check that critical string fields are preserved exactly
    critical_fields = ["version", "tenant_id"]

    field_issues =
      Enum.map(critical_fields, fn field ->
        orig_value = original[field]
        rt_value = round_tripped[field]

        if orig_value != rt_value do
          %{
            type: :critical_field_mismatch,
            field: field,
            original: orig_value,
            round_tripped: rt_value
          }
        else
          nil
        end
      end)
      |> Enum.filter(& &1)

    issues ++ field_issues
  end

  defp compile_rule(%{name: name, salience: sal, when: {:when, whens}, then: {:then, thens}}),
    do: compile_rule_core(name, sal, whens, thens)

  defp compile_rule(%{name: name, salience: {:when, whens}} = r) do
    thens =
      case r.then do
        {:then, t} -> t
        t -> t
      end

    compile_rule_core(name, nil, whens, thens)
  end

  defp compile_rule_core(name, sal, whens, thens) do
    bindings = compile_bindings(whens)
    beta_joins = compile_beta_joins(whens)
    actions = Enum.map(thens, &compile_action/1)

    # Extract accumulate nodes from when clauses
    accumulates = Enum.filter(whens, &match?({:accumulate, _, _, _, _, _}, &1))

    %{
      "id" => name,
      "name" => name,
      "salience" => (is_integer(sal) && sal) || 0,
      "bindings" => bindings,
      "beta_joins" => beta_joins,
      "actions" => actions,
      # Store for network building
      "_accumulates" => accumulates
    }
  end

  defp compile_bindings(whens) do
    whens
    |> Enum.with_index()
    |> Enum.flat_map(&compile_binding_from_when/1)
  end

  defp compile_binding_from_when({node, idx}) do
    case node do
      {:fact, binding, type, fields} ->
        [
          %{
            "binding" => binding || "_b#{idx}",
            "type" => type,
            "alpha_tests" => fields_to_alpha_tests(binding || "_b#{idx}", fields)
          }
        ]

      {:guard, _expr} ->
        []

      _other ->
        []
    end
  end

  defp compile_beta_joins(whens) do
    Enum.flat_map(whens, &compile_beta_join_from_when/1)
  end

  defp compile_beta_join_from_when({:guard, expr}), do: guard_to_beta(expr)

  defp compile_beta_join_from_when({:not, {:fact, binding, type, _fields}})
       when is_binary(binding) and is_binary(type) do
    [
      %{
        "op" => "not_exists",
        "left" => %{"binding" => binding, "field" => ""},
        "right" => %{"type" => "string", "value" => type},
        "extra" => nil
      }
    ]
  end

  defp compile_beta_join_from_when({:not, {:fact, nil, type, _fields}})
       when is_binary(type) do
    [
      %{
        "op" => "not_exists",
        "left" => %{"binding" => "", "field" => ""},
        "right" => %{"type" => "string", "value" => type},
        "extra" => nil
      }
    ]
  end

  # Handle not pattern with anonymous binding (parser produces different structure)
  defp compile_beta_join_from_when({:not, {:fact, type, {field, field_value}, _fields}})
       when is_binary(type) do
    [
      %{
        "op" => "not_exists",
        "left" => %{"binding" => "", "field" => ""},
        "right" => %{"type" => "string", "value" => type},
        "extra" => %{
          "field" => field,
          "field_value" => term(field_value)
        }
      }
    ]
  end

  defp compile_beta_join_from_when({:exists, {:fact, binding, type, _fields}})
       when is_binary(binding) and is_binary(type) do
    [
      %{
        "op" => "exists",
        "left" => %{"binding" => binding, "field" => ""},
        "right" => %{"type" => "string", "value" => type},
        "extra" => nil
      }
    ]
  end

  defp compile_beta_join_from_when({:exists, {:fact, nil, type, _fields}})
       when is_binary(type) do
    [
      %{
        "op" => "exists",
        "left" => %{"binding" => "", "field" => ""},
        "right" => %{"type" => "string", "value" => type},
        "extra" => nil
      }
    ]
  end

  # Handle exists pattern with anonymous binding
  defp compile_beta_join_from_when({:exists, {:fact, type, {field, field_value}, _fields}})
       when is_binary(type) do
    [
      %{
        "op" => "exists",
        "left" => %{"binding" => "", "field" => ""},
        "right" => %{"type" => "string", "value" => type},
        "extra" => %{
          "field" => field,
          "field_value" => term(field_value)
        }
      }
    ]
  end

  defp compile_beta_join_from_when({:not, {:exists, {:fact, binding, type, _fields}}})
       when is_binary(binding) and is_binary(type) do
    [
      %{
        "op" => "not_exists",
        "left" => %{"binding" => binding, "field" => ""},
        "right" => %{"type" => "string", "value" => type},
        "extra" => nil
      }
    ]
  end

  defp compile_beta_join_from_when({:not, {:exists, {:fact, nil, type, _fields}}})
       when is_binary(type) do
    [
      %{
        "op" => "not_exists",
        "left" => %{"binding" => "", "field" => ""},
        "right" => %{"type" => "string", "value" => type},
        "extra" => nil
      }
    ]
  end

  defp compile_beta_join_from_when(_), do: []

  defp fields_to_alpha_tests(binding, fields) do
    Enum.flat_map(fields, fn {k, v} ->
      case v do
        {:cmp, op, {:binding_ref, ^binding}, right} ->
          [%{"op" => op, "left" => binding_ref(binding, to_string(k)), "right" => term(right)}]

        {:cmp, op, left, {:binding_ref, ^binding}} ->
          [%{"op" => op, "left" => term(left), "right" => binding_ref(binding, to_string(k))}]

        {:set, kind, {:binding_ref, ^binding}, list} ->
          [
            %{
              "op" => kind,
              "left" => binding_ref(binding, to_string(k)),
              "right" => %{"type" => "list", "value" => Enum.map(list, &term/1)}
            }
          ]

        other ->
          # literal or wildcard
          [%{"op" => "==", "left" => binding_ref(binding, to_string(k)), "right" => term(other)}]
      end
    end)
  end

  defp guard_to_beta(expr), do: guard_flatten(expr)

  defp guard_flatten({:cmp, op, left, right}) do
    [%{"op" => to_string(op), "left" => term(left), "right" => term(right), "extra" => nil}]
  end

  defp guard_flatten(list) when is_list(list),
    do: Enum.flat_map(list, fn x -> guard_flatten(x) end)

  defp guard_flatten({:between, v, l, r}) do
    [%{"op" => "between", "left" => term(v), "right" => term(l), "extra" => %{"max" => term(r)}}]
  end

  defp guard_flatten({:set, kind, name, list}) do
    [
      %{
        "op" => kind,
        "left" => %{"binding" => name, "field" => ""},
        "right" => %{"type" => "list", "value" => Enum.map(list, &term/1)},
        "extra" => nil
      }
    ]
  end

  defp guard_flatten({:and, a, b}), do: guard_flatten(a) ++ guard_flatten(b)
  defp guard_flatten({:or, a, b}), do: guard_flatten(a) ++ guard_flatten(b)

  # Plugin extension point - compile custom AST nodes
  defp guard_flatten(ast_node) do
    context = %{}

    case PluginRegistry.compile_node(ast_node, context) do
      {:error, "no plugin handles node type: " <> _} ->
        # No plugin handles this - this should not happen if validation passed
        raise "unsupported guard syntax during compilation: #{inspect(ast_node)}"

      compiled_node ->
        # Plugin returned compiled IR node - convert to guard format if needed
        case compiled_node do
          # Already in guard format
          %{"op" => _} -> [compiled_node]
          # Recursively flatten compiled node
          _ -> guard_flatten(compiled_node)
        end
    end
  end

  defp compile_action({:emit, type, fields}) do
    %{
      "op" => "emit",
      "type_name" => type,
      "fields" => Enum.into(fields, %{}, fn {k, v} -> {to_string(k), term(v)} end)
    }
  end

  defp compile_action({:call, mod, fun, args}) do
    %{
      "op" => "call",
      "mfa" => %{
        "mod" => to_string(mod),
        "fun" => to_string(fun),
        "args" => Enum.map(args, &term/1)
      }
    }
  end

  defp compile_action({:log, level, message}) do
    %{
      "op" => "log",
      "level" => to_string(level),
      "message" => term(message)
    }
  end

  # Term encoding per $defs - direct objects per schema
  defp term({:binding_ref, name}),
    do: %{"binding" => name, "field" => ""}

  defp term(binding_ref: name),
    do: %{"binding" => name, "field" => ""}

  defp term({:call, name, args}),
    do: %{"name" => name, "args" => Enum.map(args, &term/1)}

  defp term({:arith, op, l, r}),
    do: %{"op" => op, "left" => term(l), "right" => term(r)}

  defp term({:date, s}), do: %{"type" => "date", "value" => s}

  defp term({:datetime, s}), do: %{"type" => "datetime", "value" => s}

  defp term(%Decimal{} = d), do: %{"type" => "decimal", "value" => Decimal.to_string(d)}

  defp term(i) when is_integer(i), do: %{"type" => "number", "value" => i}

  defp term(true), do: %{"type" => "bool", "value" => true}
  defp term(false), do: %{"type" => "bool", "value" => false}

  defp term(atom) when is_atom(atom), do: %{"type" => "string", "value" => to_string(atom)}

  defp term(list) when is_list(list) and length(list) == 1 and is_atom(hd(list)),
    do: %{"type" => "string", "value" => to_string(hd(list))}

  # Allow list-wrapped string literals that may appear from parser reductions
  defp term(list) when is_list(list) and length(list) == 1 and is_binary(hd(list)),
    do: %{"type" => "string", "value" => hd(list)}

  # Allow list-wrapped integer literals that may appear from parser reductions
  defp term(list) when is_list(list) and length(list) == 1 and is_integer(hd(list)),
    do: %{"type" => "number", "value" => hd(list)}

  defp term(bin) when is_binary(bin), do: %{"type" => "string", "value" => bin}

  defp binding_ref(binding, field), do: %{"binding" => binding, "field" => field}

  # Optimized network construction helpers (O(n log n))

  defp build_fact_type_index(rules) do
    rules
    |> Enum.reduce(%{}, fn rule, acc ->
      Enum.reduce(rule["bindings"] || [], acc, fn binding, type_acc ->
        fact_type = binding["type"]

        Map.update(
          type_acc,
          fact_type,
          %{rules: [rule["id"]], patterns: [binding], tests: binding["alpha_tests"] || []},
          fn existing ->
            %{
              rules: [rule["id"] | existing.rules],
              patterns: [binding | existing.patterns],
              tests: existing.tests ++ (binding["alpha_tests"] || [])
            }
          end
        )
      end)
    end)
    |> Enum.into(%{}, fn {fact_type, data} ->
      # Sort and deduplicate tests efficiently using Map-based deduplication
      unique_tests = deduplicate_tests_optimized(data.tests)
      {fact_type, %{data | tests: unique_tests}}
    end)
  end

  defp deduplicate_tests_optimized(tests) do
    tests
    |> Enum.reduce(%{}, fn test, acc ->
      # Create unique key from test components
      key = {test["op"], test["left"], test["right"]}
      Map.put(acc, key, test)
    end)
    |> Map.values()
    |> Enum.map(&add_selectivity_hints_optimized/1)
  end

  defp extract_patterns_batch(rules) do
    {fact_patterns, not_exists_patterns} =
      Enum.reduce(rules, {[], []}, fn rule, {facts, not_exists} ->
        # Extract fact patterns
        rule_facts =
          Enum.map(rule["bindings"] || [], fn binding ->
            %{
              "rule_id" => rule["id"],
              "binding" => binding["binding"],
              "type" => binding["type"],
              "tests" => binding["alpha_tests"] || []
            }
          end)

        # Extract not/exists patterns
        rule_not_exists =
          (rule["beta_joins"] || [])
          |> Enum.filter(fn join -> join["op"] in ["not_exists", "exists"] end)
          |> Enum.map(fn join ->
            %{
              "rule_id" => rule["id"],
              "binding" => "",
              "type" => join["right"]["value"],
              "tests" => build_tests_from_not_exists(join)
            }
          end)

        {facts ++ rule_facts, not_exists ++ rule_not_exists}
      end)

    {fact_patterns, not_exists_patterns}
  end

  defp build_alpha_nodes_batch(patterns, fact_type_index) do
    patterns
    |> Enum.group_by(fn pattern -> pattern["type"] end)
    |> Enum.map(fn {fact_type, type_patterns} ->
      # Get pre-computed unique tests from index - O(log n) lookup
      unique_tests =
        case Map.get(fact_type_index, fact_type) do
          %{tests: tests} ->
            tests

          _ ->
            # Fallback: compute tests for this type only
            type_patterns
            |> Enum.flat_map(fn pattern -> pattern["tests"] end)
            |> deduplicate_tests_optimized()
        end

      %{
        "id" => "alpha_#{fact_type}",
        "type" => fact_type,
        "tests" => unique_tests
      }
    end)
  end

  defp merge_and_deduplicate_alpha_nodes(nodes1, nodes2) do
    (nodes1 ++ nodes2)
    |> Enum.reduce(%{}, fn node, acc ->
      Map.put(acc, node["id"], node)
    end)
    |> Map.values()
  end

  defp build_binding_reference_index(rules) do
    # Build index of binding references for efficient join condition detection
    rules
    |> Enum.reduce(%{}, fn rule, acc ->
      Enum.reduce(rule["bindings"] || [], acc, fn binding, binding_acc ->
        binding_name = binding["binding"]

        # Extract field references from alpha tests AND from the original AST structure
        # We need to track which fields reference which variables
        field_refs =
          Enum.map(binding["alpha_tests"] || [], fn test ->
            case test["left"] do
              %{"field" => field} -> field
              _ -> ""
            end
          end)

        # Also extract variable references from the binding pattern
        # This requires accessing the original rule structure to find cross-references
        variable_refs = extract_variable_references_from_rule(rule, binding_name)

        Map.update(
          binding_acc,
          binding_name,
          %{
            rules: [rule["id"]],
            fields: field_refs,
            tests: binding["alpha_tests"] || [],
            variables: variable_refs
          },
          fn existing ->
            %{
              rules: [rule["id"] | existing.rules],
              fields: field_refs ++ existing.fields,
              tests: existing.tests ++ (binding["alpha_tests"] || []),
              variables: Map.merge(existing.variables, variable_refs)
            }
          end
        )
      end)
    end)
    |> Enum.into(%{}, fn {binding_name, data} ->
      # Sort and deduplicate fields
      unique_fields = Enum.uniq(data.fields)
      {binding_name, %{data | fields: unique_fields}}
    end)
  end

  # Extract variable references from the rule's original binding patterns
  defp extract_variable_references_from_rule(rule, binding_name) do
    # Look for alpha tests that contain binding references for cross-binding joins
    (rule["bindings"] || [])
    |> Enum.find(fn binding -> binding["binding"] == binding_name end)
    |> case do
      %{"alpha_tests" => alpha_tests} ->
        Enum.reduce(alpha_tests, %{}, fn test, acc ->
          case test do
            %{
              "left" => %{"binding" => ^binding_name, "field" => field},
              "right" => %{"binding" => var_binding}
            } ->
              Map.put(acc, field, var_binding)

            _ ->
              acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp build_join_nodes_optimized(rules, binding_index) do
    rules
    |> Enum.filter(fn rule -> length(rule["bindings"] || []) > 1 end)
    |> Enum.with_index()
    |> Enum.flat_map(fn {rule, idx} ->
      build_join_chain_optimized(rule, idx, binding_index)
    end)
  end

  defp build_join_chain_optimized(rule, base_idx, binding_index) do
    bindings = rule["bindings"] || []

    case length(bindings) do
      n when n <= 1 ->
        []

      _ ->
        bindings
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.with_index()
        |> Enum.map(fn {[left_binding, right_binding], join_idx} ->
          # Use pre-computed index for O(1) lookups
          join_conditions =
            find_join_conditions_optimized(
              left_binding,
              right_binding,
              binding_index
            )

          %{
            "id" => "beta_#{rule["id"]}_#{base_idx}_#{join_idx}",
            "left" => "alpha_#{left_binding["type"]}",
            "right" => "alpha_#{right_binding["type"]}",
            "on" => join_conditions,
            "post_filters" => []
          }
        end)
    end
  end

  defp find_join_conditions_optimized(left_binding, right_binding, _binding_index) do
    left_name = left_binding["binding"]
    right_name = right_binding["binding"]

    # Find join conditions by looking for shared variable references
    # Both bindings reference the same variable if their alpha tests reference the same variable binding
    left_tests = left_binding["alpha_tests"] || []
    right_tests = right_binding["alpha_tests"] || []

    # Create a map of variables to fields for each binding
    left_var_to_field =
      Enum.reduce(left_tests, %{}, fn test, acc ->
        case test do
          %{
            "left" => %{"binding" => ^left_name, "field" => field},
            "right" => %{"binding" => var_binding, "field" => ""}
          } ->
            Map.put(acc, var_binding, field)

          _ ->
            acc
        end
      end)

    right_var_to_field =
      Enum.reduce(right_tests, %{}, fn test, acc ->
        case test do
          %{
            "left" => %{"binding" => ^right_name, "field" => field},
            "right" => %{"binding" => var_binding, "field" => ""}
          } ->
            Map.put(acc, var_binding, field)

          _ ->
            acc
        end
      end)

    # Find common variables and create join conditions
    common_variables =
      MapSet.intersection(
        MapSet.new(Map.keys(left_var_to_field)),
        MapSet.new(Map.keys(right_var_to_field))
      )

    Enum.map(common_variables, fn var ->
      left_field = Map.get(left_var_to_field, var)
      right_field = Map.get(right_var_to_field, var)

      %{
        "left" => %{"binding" => left_name, "field" => left_field},
        "op" => "==",
        "right" => %{"binding" => right_name, "field" => right_field}
      }
    end)
  end

  defp build_not_exists_nodes_optimized(rules, _binding_index) do
    rules
    |> Enum.with_index()
    |> Enum.flat_map(fn {rule, rule_idx} ->
      not_exists_joins =
        (rule["beta_joins"] || [])
        |> Enum.filter(fn join -> join["op"] in ["not_exists", "exists"] end)
        |> Enum.with_index()

      Enum.map(not_exists_joins, fn {join, join_idx} ->
        fact_type = join["right"]["value"]

        # Determine left input efficiently
        left_input =
          case rule["bindings"] do
            [] ->
              "root"

            bindings ->
              last_binding = List.last(bindings)
              "alpha_#{last_binding["type"]}"
          end

        %{
          "id" => "#{join["op"]}_#{rule["id"]}_#{rule_idx}_#{join_idx}",
          "left" => left_input,
          "right" => "alpha_#{fact_type}",
          "on" => build_not_exists_join_conditions(join),
          "post_filters" => [
            %{
              "op" => join["op"],
              "left" => %{"binding" => "", "field" => ""},
              "right" => %{"type" => "string", "value" => fact_type},
              "extra" => join["extra"]
            }
          ]
        }
      end)
    end)
  end

  defp add_selectivity_hints_optimized(test) do
    base_test = %{
      "op" => test["op"],
      "left" => test["left"],
      "right" => test["right"]
    }

    # Use existing atom if available, otherwise use string
    op_key =
      case test["op"] do
        op when op in ["==", "!=", ">", "<", ">=", "<=", "in", "not_in", "between"] ->
          String.to_existing_atom(op)

        _ ->
          # Fallback for unknown operators - use string
          test["op"]
      end

    extra = %{
      "selectivity" => PredicateRegistry.selectivity_hint(op_key),
      "indexable" => PredicateRegistry.indexable?(op_key)
    }

    Map.put(base_test, "extra", extra)
  end

  # Accumulate node building functions (still needed)

  defp build_accumulate_nodes_for_rule(rule, rule_idx) do
    # Extract accumulate statements from the compiled rule
    accumulates = rule["_accumulates"] || []

    accumulates
    |> Enum.with_index()
    |> Enum.map(fn {accumulate, acc_idx} ->
      build_accumulate_node(rule, accumulate, rule_idx, acc_idx)
    end)
  end

  defp build_accumulate_node(rule, accumulate, rule_idx, acc_idx) do
    # Parse the accumulate tuple: {:accumulate, binding, fact_pattern, group_by_terms, reducers, having_clause}
    {:accumulate, _binding, fact_pattern, group_by_terms, reducers, having_clause} = accumulate

    # Extract fact type from fact_pattern
    fact_type =
      case fact_pattern do
        {:fact, type, _field_pattern, _fields} when is_binary(type) -> type
        {:fact, _binding, type, _fields} -> type
      end

    # Build accumulate node according to IR schema
    base_node = %{
      "id" => "acc_#{rule["id"]}_#{rule_idx}_#{acc_idx}",
      "from" => fact_type,
      "group_by" => compile_group_by_terms(group_by_terms),
      "reducers" => compile_reducers(reducers),
      "out_memory" => nil
    }

    # Add having clause if present
    case having_clause do
      nil ->
        base_node

      having_expr ->
        # Having clauses are guard expressions, so flatten them to predicates
        flattened_predicates = guard_flatten(having_expr)
        # For now, store the first predicate (assuming single condition)
        having_predicate = hd(flattened_predicates)
        Map.put(base_node, "having", having_predicate)
    end
  end

  defp compile_group_by_terms(group_by_terms) when is_list(group_by_terms) do
    Enum.map(group_by_terms, &term/1)
  end

  defp compile_group_by_terms(single_term) do
    [term(single_term)]
  end

  defp compile_reducers(reducers) do
    Enum.map(reducers, fn {name, reducer_spec} ->
      case reducer_spec do
        {:sum, expr} ->
          %{"name" => name, "kind" => "sum", "expr" => term(expr)}

        {:count, nil} ->
          %{"name" => name, "kind" => "count"}

        {:min, expr} ->
          %{"name" => name, "kind" => "min", "expr" => term(expr)}

        {:max, expr} ->
          %{"name" => name, "kind" => "max", "expr" => term(expr)}

        {:avg, expr} ->
          %{"name" => name, "kind" => "avg", "expr" => term(expr)}
      end
    end)
  end

  # Helper functions still used by other parts of the compiler

  defp build_tests_from_not_exists(join) do
    case join["extra"] do
      %{"field" => field, "field_value" => field_value} ->
        [
          %{
            "op" => "==",
            "left" => %{"binding" => "_anon", "field" => field},
            "right" => field_value
          }
        ]

      _ ->
        []
    end
  end

  # Keep build_not_exists_join_conditions function which is still used
  defp build_not_exists_join_conditions(join) do
    case join["extra"] do
      %{"field" => field, "field_value" => field_value} ->
        [
          %{
            "left" => %{"binding" => "", "field" => field},
            "op" => "==",
            "right" => field_value
          }
        ]

      _ ->
        []
    end
  end
end
