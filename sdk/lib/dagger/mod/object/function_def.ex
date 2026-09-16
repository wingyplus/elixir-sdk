defmodule Dagger.Mod.Object.FunctionDef do
  @moduledoc false

  # A function declaration from `Dagger.Mod.Object.defn/2`, `defn/3` or `defn/4`.

  @enforce_keys [:self, :args, :return]
  defstruct @enforce_keys ++
              [:cache_policy, check: false, generate: false, up: false, agent: false]

  @doc """
  Convert a `fun_def` into Dagger Function.

  `docs` are the docs of the module declaring it, from
  `Dagger.Mod.Object.docs/1`, and `type_ids` the ids of the types it uses, from
  `Dagger.Mod.Object.TypeDef.resolve/2`.
  """
  def to_dag_function(%__MODULE__{} = fun_def, name, docs, type_ids, %Dagger.Client{} = dag)
      when is_atom(name) do
    {doc, deprecated} = Map.get(docs.functions, name, {nil, nil})

    dag
    |> Dagger.Client.function(
      Dagger.Mod.Helper.camelize(name),
      Map.fetch!(type_ids, fun_def.return)
    )
    |> maybe_with_description(doc)
    |> maybe_with_cache_policy(fun_def.cache_policy)
    |> maybe_with_deprecated(deprecated)
    |> maybe_with_check(fun_def.check)
    |> maybe_with_generator(fun_def.generate)
    |> maybe_with_up(fun_def.up)
    |> maybe_with_agent(fun_def.agent)
    |> with_args(fun_def.args, type_ids)
  end

  @doc """
  The types `fun_def` refers to: its arguments' and its return type.
  """
  def types(%__MODULE__{} = fun_def) do
    [fun_def.return | Enum.map(fun_def.args, fn {_name, arg_def} -> arg_def[:type] end)]
  end

  defp maybe_with_deprecated(function, nil), do: function

  defp maybe_with_deprecated(function, {:deprecated, reason}),
    do: Dagger.Function.with_deprecated(function, reason: reason)

  defp maybe_with_check(function, true), do: Dagger.Function.with_check(function)
  defp maybe_with_check(function, _), do: function

  defp maybe_with_generator(function, true), do: Dagger.Function.with_generator(function)
  defp maybe_with_generator(function, _), do: function

  defp maybe_with_up(function, true), do: Dagger.Function.with_up(function)
  defp maybe_with_up(function, _), do: function

  defp maybe_with_agent(function, true), do: Dagger.Function.with_agent(function)
  defp maybe_with_agent(function, _), do: function

  defp maybe_with_cache_policy(function, nil), do: function

  defp maybe_with_cache_policy(function, {:ttl, ttl}) do
    Dagger.Function.with_cache_policy(function, Dagger.FunctionCachePolicy.default(),
      time_to_live: ttl
    )
  end

  defp maybe_with_cache_policy(function, :default),
    do: Dagger.Function.with_cache_policy(function, Dagger.FunctionCachePolicy.default())

  defp maybe_with_cache_policy(function, :never),
    do: Dagger.Function.with_cache_policy(function, Dagger.FunctionCachePolicy.never())

  defp maybe_with_cache_policy(function, :per_session),
    do: Dagger.Function.with_cache_policy(function, Dagger.FunctionCachePolicy.per_session())

  defp maybe_with_description(function, nil), do: function
  defp maybe_with_description(function, doc), do: Dagger.Function.with_description(function, doc)

  defp with_args(fun, args, type_ids) do
    args
    |> Enum.reduce(fun, fn {name, arg_def}, fun ->
      type_def = Map.fetch!(type_ids, Keyword.fetch!(arg_def, :type))

      opts =
        arg_def
        |> Keyword.take([:doc, :default, :default_path, :ignore, :deprecated])
        |> Enum.reject(fn {_, value} -> is_nil(value) end)
        |> Enum.map(&normalize_arg_option/1)

      fun
      # The API takes argument names as strings; `defn` declares them as atoms.
      |> Dagger.Function.with_arg(to_string(name), type_def, opts)
    end)
  end

  defp normalize_arg_option({:doc, doc}), do: {:description, doc}

  defp normalize_arg_option({:default, default_value}),
    do: {:default_value, Jason.encode!(default_value)}

  defp normalize_arg_option(opt), do: opt
end
