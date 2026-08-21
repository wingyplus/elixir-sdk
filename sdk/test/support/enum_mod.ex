defmodule SimpleEnum do
  @moduledoc """
  A severity level.
  """
  use Dagger.Mod.Enum, name: "SimpleEnum", values: [:unknown, :low, :high]
end

defmodule EnumWithOption do
  @moduledoc false
  use Dagger.Mod.Enum,
    name: "EnumWithOption",
    values: [:low, :high, unknown: [doc: "Unknown severity"]]
end

defmodule EnumAliasValue do
  @moduledoc false
  use Dagger.Mod.Enum,
    name: "EnumAliasValue",
    values: [UNKNOWN: "unknown", LOW: {"low", doc: "Low severity"}]
end

defmodule EnumWithDeprecatedMember do
  @moduledoc false
  use Dagger.Mod.Enum,
    name: "EnumWithDeprecatedMember",
    values: [
      :high,
      low: [deprecated: "Use `high` instead."],
      medium: {"MEDIUM", doc: "Medium severity", deprecated: "Use `high` instead."}
    ]
end
