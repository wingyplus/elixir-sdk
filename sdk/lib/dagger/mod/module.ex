defmodule Dagger.Mod.Module do
  @moduledoc false

  alias Dagger.Mod.Helper
  alias Dagger.Mod.ID
  alias Dagger.Mod.Object
  alias Dagger.Mod.Registry
  alias Dagger.Mod.Object.FieldDef
  alias Dagger.Mod.Object.FunctionDef
  alias Dagger.Mod.Object.TypeDef

  @doc """
  Define a Dagger module from the given module.
  """
  @spec define(Dagger.Client.t(), module()) :: Dagger.Module.t()
  def define(dag, module) when is_struct(dag, Dagger.Client) and is_atom(module) do
    # Everything the module is made of reaches the engine by id, and fetching
    # the ids one at a time made registration a round-trip for every type,
    # function and object. They are fetched in bulk instead, in dependency
    # order: the types first, then the functions that use them, then the
    # objects that hold those.
    modules = module |> Registry.register() |> Registry.all_modules()
    {objects, enums} = Enum.split_with(modules, &(&1.__kind__() == :object))

    objects = Enum.map(objects, &{&1, Object.docs(&1)})
    type_ids = TypeDef.resolve(dag, enums ++ Enum.flat_map(objects, &types/1))
    object_ids = define_objects(dag, objects, type_ids)

    modules
    |> Enum.reduce(Dagger.Client.module(dag), fn module, dag_module ->
      case Map.fetch(object_ids, module) do
        {:ok, id} -> Dagger.Module.with_object(dag_module, id)
        :error -> Dagger.Module.with_enum(dag_module, Map.fetch!(type_ids, module))
      end
    end)
    |> maybe_with_description(Object.get_module_doc(module))
  end

  defp maybe_with_description(module, nil), do: module
  defp maybe_with_description(module, doc), do: Dagger.Module.with_description(module, doc)

  defp types({module, _docs}) do
    fields = Enum.map(module.__object__(:fields), fn {_name, field_def} -> field_def.type end)
    functions = Enum.flat_map(module.__object__(:functions), &FunctionDef.types(elem(&1, 1)))
    fields ++ functions
  end

  # Every function of every object, then every object, a round-trip each.
  defp define_objects(dag, objects, type_ids) do
    functions =
      for {module, docs} <- objects, {name, fun_def} <- module.__object__(:functions) do
        {{module, name}, FunctionDef.to_dag_function(fun_def, name, docs, type_ids, dag)}
      end

    function_ids = load_ids(dag, functions)

    objects
    |> Enum.map(fn {module, docs} ->
      {module, define_object(dag, module, docs, type_ids, function_ids)}
    end)
    |> then(&load_ids(dag, &1))
  end

  defp load_ids(dag, keyed) do
    {keys, resources} = Enum.unzip(keyed)
    Map.new(Enum.zip(keys, ID.load!(dag, resources)))
  end

  defp define_object(dag, module, docs, type_ids, function_ids) do
    mod_name = module.__object__(:name)

    dag
    |> Dagger.Client.type_def()
    |> Dagger.TypeDef.with_object(Helper.camelize(mod_name), object_options(docs))
    |> define_fields(module, type_ids)
    |> define_functions(module, function_ids)
    |> define_constructor(module, function_ids)
  end

  defp object_options(docs) do
    []
    |> maybe_put_optional({:description, docs.doc})
    |> maybe_put_optional(docs.deprecated)
  end

  defp maybe_put_optional(opts, nil), do: opts
  defp maybe_put_optional(opts, {key, val}), do: Keyword.put(opts, key, val)

  def define_enum(dag, module) do
    mod_name = module.__name__()

    type_def =
      dag
      |> Dagger.Client.type_def()
      |> Dagger.TypeDef.with_enum(Helper.camelize(mod_name),
        description: Object.get_module_doc(module)
      )

    module
    |> Dagger.Mod.Enum.keys()
    |> Enum.reduce(type_def, fn key, tdef ->
      # The engine names the member by its key and hands that name back to the
      # module at call time. The declared value rides along as `value`: it is
      # what a dependent SDK generates its constant from.
      opts =
        []
        |> maybe_put_optional({:value, Dagger.Mod.Enum.get_key_value(module, key)})
        |> maybe_put_optional({:description, Dagger.Mod.Enum.get_key_description(module, key)})
        |> maybe_put_optional({:deprecated, Dagger.Mod.Enum.get_key_deprecated(module, key)})

      Dagger.TypeDef.with_enum_member(tdef, Atom.to_string(key), opts)
    end)
  end

  defp define_constructor(type_def, module, function_ids) do
    case Enum.find(module.__object__(:functions), &init?/1) do
      nil ->
        type_def

      {name, _fun_def} ->
        Dagger.TypeDef.with_constructor(type_def, Map.fetch!(function_ids, {module, name}))
    end
  end

  defp define_fields(type_def, module, type_ids) do
    module.__object__(:fields)
    |> Enum.reduce(type_def, fn {name, field_def}, type_def ->
      FieldDef.define(field_def, name, type_def, type_ids)
    end)
  end

  defp define_functions(type_def, module, function_ids) do
    module.__object__(:functions)
    |> Enum.reject(&init?/1)
    |> Enum.reduce(type_def, fn {name, _fun_def}, type_def ->
      Dagger.TypeDef.with_function(type_def, Map.fetch!(function_ids, {module, name}))
    end)
  end

  defp init?({:init, _}), do: true
  defp init?({_, _}), do: false
end
