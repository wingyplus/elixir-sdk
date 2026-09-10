defmodule Objects.AuthKind do
  @moduledoc false

  # Declared for `Objects.C.kind` and used nowhere else: this enum is never a
  # function argument, so it is only registered if fields are walked too.
  use Dagger.Mod.Enum, name: "ObjectsAuthKind", values: [:SERVICE_ACCOUNT, :TOKEN]
end
