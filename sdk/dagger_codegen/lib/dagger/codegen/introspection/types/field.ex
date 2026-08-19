defmodule Dagger.Codegen.Introspection.Types.Field do
  @moduledoc """
  A field on a GraphQL object or interface.
  """

  alias Dagger.Codegen.Introspection.Types.Directive
  alias Dagger.Codegen.Introspection.Types.InputValue
  alias Dagger.Codegen.Introspection.Types.TypeRef

  @type t :: %__MODULE__{
          args: [InputValue.t()],
          deprecation_reason: String.t() | nil,
          description: String.t() | nil,
          name: String.t(),
          type: TypeRef.t(),
          directives: [Directive.t()]
        }

  defstruct [:deprecation_reason, :description, :name, :type, args: [], directives: []]

  def from_map(
        %{
          "args" => args,
          "deprecationReason" => deprecation_reason,
          "description" => description,
          "name" => name,
          "type" => type
        } = field
      ) do
    %__MODULE__{
      args: Enum.map(args, &InputValue.from_map/1),
      deprecation_reason: deprecation_reason,
      description: description,
      name: name,
      type: TypeRef.from_map(type),
      directives: Enum.map(field["directives"] || [], &Directive.from_map/1)
    }
  end
end
