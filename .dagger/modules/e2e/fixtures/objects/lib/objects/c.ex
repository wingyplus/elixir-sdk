defmodule Objects.C do
  @moduledoc false

  use Dagger.Mod.Object, name: "ObjectsC"

  object do
    field :kind, Objects.AuthKind.t() | nil
  end

  defn message() :: String.t() do
    "Hello from C"
  end
end
