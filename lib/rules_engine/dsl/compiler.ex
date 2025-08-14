defmodule RulesEngine.DSL.Compiler do
  @moduledoc """
  Parse and compile DSL to IR per specs/ir.schema.json.
  """
  alias RulesEngine.DSL.{Parser, Validate}

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
    with {:ok, ast, _warn} <- parse(source, opts),
         {:ok, _ast} <- Validate.validate(ast, opts) do
      checksum = Base.encode16(:crypto.hash(:sha256, normalise_source(source)), case: :lower)
      compile(tenant_id, ast, Map.put(opts, :source_checksum, checksum))
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

    {:ok,
     %{
       "version" => "v1",
       "tenant_id" => tenant_id,
       "source_checksum" => Map.get(opts, :source_checksum),
       "compiled_at" => now,
       "rules" => rules,
       "network" => %{
         "alpha" => [],
         "beta" => [],
         "accumulate" => build_accumulate_nodes(rules),
         "agenda" => []
       }
     }}
  end

  defp build_accumulate_nodes(_rules) do
    # For now, no true linking; emit nodes based on rule ids and placeholders if present in rule source in the future
    []
  end

  defp validate_ir_schema(ir) do
    schema_path = Path.expand("../../../specs/ir.schema.json", __DIR__)

    schema =
      schema_path
      |> File.read!()
      |> Jason.decode!()

    {:ok, root} = JSV.build(schema)

    case JSV.validate(ir, root) do
      {:ok, _} -> :ok
      {:error, errors} -> {:error, [%{code: :schema_validation_failed, errors: errors}]}
    end
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

    # accumulate nodes (minimal): collect any {:accumulate, ...} in whens and emit network nodes
    _accs = Enum.filter(whens, &match?({:accumulate, _, _, _, _, _}, &1))

    %{
      "id" => name,
      "name" => name,
      "salience" => (is_integer(sal) && sal) || 0,
      "bindings" => bindings,
      "beta_joins" => beta_joins,
      "actions" => actions
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

  defp compile_beta_join_from_when({:not, {:fact, binding, type, _fields}}) do
    [
      %{
        "op" => "not_exists",
        "left" => %{"binding" => binding || "", "field" => ""},
        "right" => %{"type" => "string", "value" => to_string(type)},
        "extra" => nil
      }
    ]
  end

  defp compile_beta_join_from_when({:exists, {:fact, binding, type, _fields}}) do
    [
      %{
        "op" => "exists",
        "left" => %{"binding" => binding || "", "field" => ""},
        "right" => %{"type" => "string", "value" => to_string(type)},
        "extra" => nil
      }
    ]
  end

  defp compile_beta_join_from_when({:not, {:exists, {:fact, binding, type, _fields}}}) do
    [
      %{
        "op" => "not_exists",
        "left" => %{"binding" => binding || "", "field" => ""},
        "right" => %{"type" => "string", "value" => to_string(type)},
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

  defp compile_action({:emit, type, fields}) do
    %{
      "op" => "emit",
      "type_name" => type,
      "fields" => Enum.into(fields, %{}, fn {k, v} -> {to_string(k), term(v)} end)
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

  defp term(bin) when is_binary(bin), do: %{"type" => "string", "value" => bin}

  defp binding_ref(binding, field), do: %{"binding" => binding, "field" => field}
end
