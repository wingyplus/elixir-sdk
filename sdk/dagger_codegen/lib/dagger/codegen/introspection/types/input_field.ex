defmodule Dagger.Codegen.Introspection.Types.InputValue do
  @moduledoc """
  An argument to a field, or a field on an input object.
  """

  alias Dagger.Codegen.Introspection.Types.Directive
  alias Dagger.Codegen.Introspection.Types.TypeRef

  @type t :: %__MODULE__{
          description: String.t() | nil,
          name: String.t(),
          type: TypeRef.t(),
          directives: [Directive.t()]
        }

  defstruct [:description, :name, :type, directives: []]

  @doc """
  Whether the value may be omitted. GraphQL says so by not wrapping it in `NON_NULL`.
  """
  def is_optional?(%__MODULE__{} = input_value), do: input_value.type.kind != "NON_NULL"

  def from_map(%{"description" => description, "name" => name, "type" => type} = input_value) do
    %__MODULE__{
      description: description,
      name: name,
      type: TypeRef.from_map(type),
      directives: Enum.map(input_value["directives"] || [], &Directive.from_map/1)
    }
  end
end
