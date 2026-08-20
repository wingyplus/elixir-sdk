defmodule Dagger.Codegen.Introspection.Types.Schema do
  @moduledoc """
  A GraphQL introspection schema, reduced to what the generator reads.
  """

  alias Dagger.Codegen.Introspection.Types.Type

  @type t :: %__MODULE__{types: [Type.t()]}

  defstruct types: []

  @doc """
  Convert a schema map from introspection.json into a struct.
  """
  def from_map(%{"types" => types}) do
    %__MODULE__{types: Enum.map(types, &Type.from_map/1)}
  end
end
