defmodule Dagger.Mod.Object.Options do
  @moduledoc false

  # Compile-time normalization and validation of `Dagger.Mod.Object.defn/3`
  # options.
  #
  # Accepts either a bare flag (`:check`) or a list mixing bare flags and
  # keyword pairs (`[:check, cache: {:ttl, "30s"}]`), and returns a keyword
  # list with every key filled in. Every value is an AST literal, so the
  # result can be `unquote`d straight into a `Dagger.Mod.Object.FunctionDef`.

  @flags [:check, :generate, :up, :agent]

  # The flags the engine runs on its own, so nobody is left to supply an
  # argument. `:agent` is not one of them: the compose fold hands it a base
  # `LLM`, which it declares as a required argument.
  @no_arg_flags [:check, :generate, :up]

  @keys @flags ++ [:cache]
  @policies [:default, :never, :per_session]
  @defaults [check: false, generate: false, up: false, agent: false, cache: nil]

  # Go duration string, e.g. "30s", "1h", "1h30m", "1.5h".
  @duration ~r/^(\d+(\.\d+)?(ns|us|µs|ms|s|m|h))+$/

  @doc """
  Normalize and validate the options given to `defn`.

  Raises `ArgumentError` on any unknown option, duplicate option, bad value,
  or option that cannot apply to `fun_name`.
  """
  @spec normalize!(term(), atom()) :: keyword()
  def normalize!(opts, fun_name) when is_atom(fun_name) do
    opts
    |> List.wrap()
    |> Enum.map(&expand(&1, fun_name))
    |> reject_duplicates!(fun_name)
    |> then(&Keyword.merge(@defaults, &1))
    |> validate_values!(fun_name)
    |> reject_unsupported!(fun_name)
  end

  # Every flag is boolean, so a bare atom means "on".
  defp expand(flag, _fun_name) when flag in @flags, do: {flag, true}
  defp expand({key, value}, _fun_name) when key in @keys, do: {key, value}

  defp expand({key, _value}, fun_name) when is_atom(key) do
    raise ArgumentError, unknown(key, fun_name)
  end

  defp expand(flag, fun_name) when is_atom(flag) do
    raise ArgumentError, unknown(flag, fun_name)
  end

  defp expand(other, fun_name) do
    raise ArgumentError,
          "invalid option #{inspect(other)} for `defn #{fun_name}`. " <>
            "Expected a flag (#{inspect(@flags)}) or a keyword pair (#{inspect(@keys)})"
  end

  defp unknown(key, fun_name) do
    "unknown option #{inspect(key)} for `defn #{fun_name}`. " <>
      "The supported options are #{inspect(@keys)}"
  end

  defp reject_duplicates!(opts, fun_name) do
    keys = Keyword.keys(opts)

    case keys -- Enum.uniq(keys) do
      [] ->
        opts

      [key | _] ->
        raise ArgumentError,
              "option #{inspect(key)} was given more than once to `defn #{fun_name}`"
    end
  end

  defp validate_values!(opts, fun_name) do
    Enum.each(opts, &validate_value!(&1, fun_name))
    opts
  end

  defp validate_value!({flag, value}, _fun_name) when flag in @flags and is_boolean(value),
    do: :ok

  defp validate_value!({flag, value}, fun_name) when flag in @flags do
    raise ArgumentError,
          "expected #{inspect(flag)} to be a boolean in `defn #{fun_name}`, " <>
            "got: #{inspect(value)}. Write it as the flag #{inspect(flag)} to enable it"
  end

  defp validate_value!({:cache, nil}, _fun_name), do: :ok
  defp validate_value!({:cache, policy}, _fun_name) when policy in @policies, do: :ok

  defp validate_value!({:cache, {:ttl, ttl}}, fun_name) when is_binary(ttl) do
    unless Regex.match?(@duration, ttl) do
      raise ArgumentError,
            "invalid cache ttl #{inspect(ttl)} in `defn #{fun_name}`. " <>
              ~s|Expected a duration string such as "30s", "10m" or "1h30m"|
    end

    :ok
  end

  defp validate_value!({:cache, value}, fun_name) do
    raise ArgumentError,
          "invalid `cache` option #{inspect(value)} in `defn #{fun_name}`. " <>
            ~s|Expected one of #{inspect(@policies)} or `{:ttl, "30s"}`|
  end

  @doc """
  Validate the flags against the signature they were declared on.

  `arg_defs` is the compiled argument list (already stripped of `self`) and
  `return_def` the compiled return type, both as produced by
  `Dagger.Mod.Object.defn/3`.

  Every rule here mirrors one the engine applies in `validateObjectFunction`
  when the module is loaded (`core/module.go`); catching them at compile time
  turns a run-time failure into an error at the `defn` that declared it.

  Raises `ArgumentError` when a flag's contract is violated:

    * `:generate` must return the core `Changeset!` type, `:up` the core
      `Service!` type and `:agent` the core `LLM!` type.

    * `:check`, `:generate` and `:up` must be callable with no caller-supplied
      arguments. `dagger check`, `dagger generate` and `dagger up` discover and
      run these functions on their own, so there is nobody to supply a required
      argument.

    * `:agent` must declare exactly one required argument, the base `LLM` the
      compose fold supplies. Any other required argument is rejected.
  """
  @spec validate_signature!(keyword(), atom(), keyword(), term()) :: :ok
  def validate_signature!(opts, fun_name, arg_defs, return_def) when is_atom(fun_name) do
    Enum.each(@flags, fn flag ->
      if opts[flag] do
        validate_return!(return_def, flag, fun_name)
      end
    end)

    Enum.each(@no_arg_flags, fn flag ->
      if opts[flag] do
        validate_no_required_args!(arg_defs, flag, fun_name)
      end
    end)

    if opts[:agent] do
      validate_agent_base_arg!(arg_defs, fun_name)
    end

    :ok
  end

  # `:check` constrains only the arguments, never the return type: a check
  # fails by raising, or by returning a container whose last command exited
  # non-zero.
  defp validate_return!(_return_def, :check, _fun_name), do: :ok

  defp validate_return!(return_def, flag, fun_name) do
    validate_core_return!(return_def, core_return(flag), flag, fun_name)
  end

  defp core_return(:generate), do: Dagger.Changeset
  defp core_return(:up), do: Dagger.Service
  defp core_return(:agent), do: Dagger.LLM

  defp validate_core_return!(module, module, _flag, _fun_name), do: :ok

  defp validate_core_return!({:optional, module}, module, flag, fun_name) do
    raise ArgumentError,
          "the return type of `defn #{fun_name}` must not be optional because it is " <>
            "declared #{inspect(flag)}. Write it as `#{inspect(module)}.t()`, not " <>
            "`#{inspect(module)}.t() | nil`"
  end

  defp validate_core_return!(return_def, module, flag, fun_name) do
    raise ArgumentError,
          "`defn #{fun_name}` is declared #{inspect(flag)}, so it must return " <>
            "`#{inspect(module)}.t()`, got: `#{describe_type(return_def)}`"
  end

  # The base the compose fold supplies is the one required argument an agent
  # may declare.
  defp validate_agent_base_arg!(arg_defs, fun_name) do
    arg_defs
    |> Enum.filter(&required?/1)
    |> exempt_base(false, fun_name)
  end

  # Walks the required arguments the way `validateAgentFunction` does: the
  # first `LLM` among them is the base and is exempt, and anything else that
  # is still required is an error.
  defp exempt_base([], true, _fun_name), do: :ok

  defp exempt_base([], false, fun_name) do
    raise ArgumentError,
          "`defn #{fun_name}` is declared :agent, so it must declare a required " <>
            "`Dagger.LLM.t()` argument, the base the compose fold supplies"
  end

  defp exempt_base([{name, meta} | rest], exempted?, fun_name) do
    if not exempted? and meta[:type] == Dagger.LLM do
      exempt_base(rest, true, fun_name)
    else
      raise ArgumentError, extra_agent_arg(fun_name, name)
    end
  end

  defp extra_agent_arg(fun_name, name) do
    "`defn #{fun_name}` is declared :agent, but declares the required argument " <>
      "`#{name}`. An :agent function may only require a single `Dagger.LLM.t()` " <>
      "argument, the base the compose fold supplies. Give the argument a " <>
      "`:default` or a `:default_path`, or type it as optional (`type | nil`)"
  end

  # A required argument is one the caller has to supply: not optional, and
  # with no value the engine can fill in. This mirrors `argRequired` in the
  # engine (`core/module.go`).
  #
  # `self` never reaches here — it is stripped while compiling the argument
  # list — so a function that only takes the object itself is fine.
  defp validate_no_required_args!(arg_defs, flag, fun_name) do
    case Enum.filter(arg_defs, &required?/1) do
      [] ->
        :ok

      required ->
        names = required |> Enum.map_join(", ", fn {name, _} -> "`#{name}`" end)

        raise ArgumentError,
              "`defn #{fun_name}` is declared #{inspect(flag)}, so it must be callable " <>
                "with no arguments, but #{names} #{verb(required)} required. " <>
                "Give the argument a `:default` or a `:default_path`, or type it as " <>
                "optional (`type | nil`)"
    end
  end

  defp required?({_name, meta}) do
    not match?({:optional, _}, meta[:type]) and
      is_nil(meta[:default]) and is_nil(meta[:default_path])
  end

  defp verb([_]), do: "is"
  defp verb(_), do: "are"

  # Render a compiled type back into something close to what was written, for
  # error messages.
  defp describe_type(:integer), do: "integer()"
  defp describe_type(:float), do: "float()"
  defp describe_type(:boolean), do: "boolean()"
  defp describe_type(:string), do: "String.t()"
  defp describe_type({:list, type}), do: "[#{describe_type(type)}]"
  defp describe_type({:optional, type}), do: "#{describe_type(type)} | nil"
  defp describe_type(module) when is_atom(module), do: "#{inspect(module)}.t()"

  # `init` becomes the object constructor, where neither flag has any meaning.
  defp reject_unsupported!(opts, :init) do
    Enum.each(@flags, fn flag ->
      if opts[flag] do
        raise ArgumentError,
              "#{inspect(flag)} cannot be used on `defn init`, which declares the " <>
                "object constructor rather than a callable function"
      end
    end)

    opts
  end

  defp reject_unsupported!(opts, _fun_name), do: opts
end
