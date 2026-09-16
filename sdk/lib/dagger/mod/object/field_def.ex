defmodule Dagger.Mod.Object.FieldDef do
  @moduledoc false

  # A field definition for declaring a field in the object.

  @enforce_keys [:type, :doc]
  defstruct @enforce_keys ++ [:deprecated]

  @doc """
  Define a Dagger Field from `field_def`, taking the id of its type from
  `type_ids`, as `Dagger.Mod.Object.TypeDef.resolve/2` builds it.
  """
  def define(%__MODULE__{} = field_def, name, type_def, type_ids) do
    type_def
    # The API takes field names as strings; `field` declares them as atoms.
    |> Dagger.TypeDef.with_field(
      to_string(name),
      Map.fetch!(type_ids, field_def.type),
      to_field_opts(field_def)
    )
  end

  defp to_field_opts(field_def) do
    opts = []
    opts = Keyword.put(opts, :deprecated, field_def.deprecated)

    if field_def.doc do
      [{:description, field_def.doc} | opts]
    else
      opts
    end
  end
end
