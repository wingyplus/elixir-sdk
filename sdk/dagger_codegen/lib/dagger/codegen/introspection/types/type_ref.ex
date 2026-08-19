defmodule Dagger.Codegen.Introspection.Types.TypeRef do
  @moduledoc """
  A GraphQL type reference, in wire shape.

  See `Dagger.Codegen.Type` for the normalized form everything
  downstream actually works with.
  """

  @type t :: %__MODULE__{kind: String.t(), name: String.t() | nil, of_type: t() | nil}

  defstruct [
    :kind,
    :name,
    :of_type
  ]

  def from_map(%{"kind" => kind} = type_ref) do
    %__MODULE__{
      kind: kind,
      name: type_ref["name"],
      of_type:
        case type_ref["ofType"] do
          nil -> nil
          of_type -> from_map(of_type)
        end
    }
  end
end
