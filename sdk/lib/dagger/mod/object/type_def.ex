defmodule Dagger.Mod.Object.TypeDef do
  @moduledoc false

  # A set of functions for working with type system in the SDK.

  alias Dagger.Mod.ID

  @doc """
  Resolve the id of every type in `types`, and of every type nested in them.

  Returns a map from type to its `Dagger.TypeDef`, with its id loaded. A type is
  resolved once however often it is used, and all the types at the same depth of
  nesting go in one round-trip: a list needs the id of its element type, so
  element types are resolved first.
  """
  def resolve(dag, types) do
    types
    |> Enum.flat_map(&with_nested/1)
    |> Enum.uniq()
    |> Enum.group_by(&depth/1)
    |> Enum.sort()
    |> Enum.reduce(%{}, fn {_depth, types}, ids ->
      type_defs = Enum.map(types, &define(dag, &1, ids))
      Map.merge(ids, Map.new(Enum.zip(types, ID.load!(dag, type_defs))))
    end)
  end

  defp with_nested({wrapper, type} = t) when wrapper in [:list, :optional],
    do: [t | with_nested(type)]

  defp with_nested(type), do: [type]

  defp depth({wrapper, type}) when wrapper in [:list, :optional], do: depth(type) + 1
  defp depth(_type), do: 0

  @doc """
  Define a Dagger TypeDef from `type`, taking the ids of the element types of
  its lists from `ids`, as `resolve/2` builds it.
  """
  def define(dag, type, ids) do
    define(dag, Dagger.Client.type_def(dag), type, ids)
  end

  defp define(_dag, type_def, :integer, _ids) do
    type_def
    |> Dagger.TypeDef.with_kind(Dagger.TypeDefKind.integer_kind())
  end

  defp define(_dag, type_def, :float, _ids) do
    type_def
    |> Dagger.TypeDef.with_kind(Dagger.TypeDefKind.float_kind())
  end

  defp define(_dag, type_def, :boolean, _ids) do
    type_def
    |> Dagger.TypeDef.with_kind(Dagger.TypeDefKind.boolean_kind())
  end

  defp define(_dag, type_def, :string, _ids) do
    type_def
    |> Dagger.TypeDef.with_kind(Dagger.TypeDefKind.string_kind())
  end

  defp define(_dag, type_def, {:list, type}, ids) do
    type_def
    |> Dagger.TypeDef.with_list_of(Map.fetch!(ids, type))
  end

  defp define(dag, type_def, {:optional, type}, ids) do
    dag
    |> define(type_def, type, ids)
    |> Dagger.TypeDef.with_optional(true)
  end

  defp define(dag, type_def, module, _ids) do
    name = module.__name__()

    case module.__kind__() do
      :object ->
        Dagger.TypeDef.with_object(type_def, name)

      :scalar ->
        if name == "Void" do
          type_def
          |> Dagger.TypeDef.with_kind(Dagger.TypeDefKind.void_kind())
          |> Dagger.TypeDef.with_optional(true)
        else
          Dagger.TypeDef.with_scalar(type_def, name)
        end

      :enum ->
        Dagger.Mod.Module.define_enum(dag, module)
    end
  end
end
