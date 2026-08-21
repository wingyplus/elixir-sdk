defmodule Dagger.Mod.Object.Options do
  @moduledoc false

  # Compile-time normalization and validation of `Dagger.Mod.Object.defn/3`
  # options.
  #
  # Accepts either a bare flag (`:check`) or a list mixing bare flags and
  # keyword pairs (`[:check, cache: {:ttl, "30s"}]`), and returns a keyword
  # list with every key filled in. Every value is an AST literal, so the
  # result can be `unquote`d straight into a `Dagger.Mod.Object.FunctionDef`.

  @flags [:check, :generate]
  @keys [:check, :generate, :cache]
  @policies [:default, :never, :per_session]
  @defaults [check: false, generate: false, cache: nil]

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

  # `:check` and `:generate` are flags, so a bare atom means "on".
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

  Raises `ArgumentError` when a flag's contract is violated:

    * `:generate` must return the core `Changeset!` type. The engine enforces
      this in `validateGeneratorFunction` when the module is loaded; catching
      it here turns a run-time failure into a compile error.

    * `:generate` and `:check` must be callable with no caller-supplied
      arguments. `dagger check` and `dagger generate` discover and run these
      functions on their own, so there is nobody to supply a required
      argument.
  """
  @spec validate_signature!(keyword(), atom(), keyword(), term()) :: :ok
  def validate_signature!(opts, fun_name, arg_defs, return_def) when is_atom(fun_name) do
    if opts[:generate] do
      validate_generator_return!(return_def, fun_name)
    end

    Enum.each(@flags, fn flag ->
      if opts[flag] do
        validate_no_required_args!(arg_defs, flag, fun_name)
      end
    end)

    :ok
  end

  defp validate_generator_return!(Dagger.Changeset, _fun_name), do: :ok

  defp validate_generator_return!({:optional, Dagger.Changeset}, fun_name) do
    raise ArgumentError,
          "the return type of `defn #{fun_name}` must not be optional because it is " <>
            "declared :generate. Write it as `Dagger.Changeset.t()`, not " <>
            "`Dagger.Changeset.t() | nil`"
  end

  defp validate_generator_return!(return_def, fun_name) do
    raise ArgumentError,
          "`defn #{fun_name}` is declared :generate, so it must return " <>
            "`Dagger.Changeset.t()`, got: `#{describe_type(return_def)}`"
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
