defmodule Dagger.Codegen.Introspection.Types.Type do
  @moduledoc """
  A GraphQL type, reduced to what the generator reads.
  """

  alias Dagger.Codegen.Introspection.Types.EnumValue
  alias Dagger.Codegen.Introspection.Types.Field
  alias Dagger.Codegen.Introspection.Types.InputValue

  @type t :: %__MODULE__{
          description: String.t() | nil,
          enum_values: [EnumValue.t()],
          fields: [Field.t()],
          input_fields: [InputValue.t()],
          kind: String.t(),
          name: String.t()
        }

  defstruct [:description, :kind, :name, enum_values: [], fields: [], input_fields: []]

  def from_map(%{"kind" => kind, "name" => name} = type) do
    %__MODULE__{
      description: type["description"],
      enum_values: Enum.map(type["enumValues"] || [], &EnumValue.from_map/1),
      fields: Enum.map(type["fields"] || [], &Field.from_map/1),
      input_fields: Enum.map(type["inputFields"] || [], &InputValue.from_map/1),
      kind: kind,
      name: name
    }
  end
end
