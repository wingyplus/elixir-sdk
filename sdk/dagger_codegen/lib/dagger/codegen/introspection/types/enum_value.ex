defmodule Dagger.Codegen.Introspection.Types.EnumValue do
  @moduledoc """
  One member of a GraphQL enum.
  """

  alias Dagger.Codegen.Introspection.Types.Directive

  @type t :: %__MODULE__{
          description: String.t() | nil,
          name: String.t(),
          directives: [Directive.t()]
        }

  defstruct [:description, :name, directives: []]

  def from_map(%{"description" => description, "name" => name} = enum_value) do
    %__MODULE__{
      description: description,
      name: name,
      directives: Enum.map(enum_value["directives"] || [], &Directive.from_map/1)
    }
  end
end
