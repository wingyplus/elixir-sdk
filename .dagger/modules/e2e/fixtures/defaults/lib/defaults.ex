defmodule BasicEnum do
  @moduledoc false

  use Dagger.Mod.Enum, name: "BasicEnum", values: [:FOO, BAR: {"BAR", doc: "bar"}, GAR: "GAR"]
end

defmodule AliasEnum do
  @moduledoc false

  # Every member declares a wire value that differs from its key, so the key and
  # the value can never be mistaken for one another.
  use Dagger.Mod.Enum,
    name: "AliasEnum",
    values: [UNKNOWN: "unknown", LOW: {"low", doc: "Low severity"}, HIGH: "critical"]
end

defmodule Defaults do
  @moduledoc false

  use Dagger.Mod.Object, name: "Defaults"

  defn echo_else(value: String.t() | nil) :: String.t() do
    if(value, do: value, else: "default value if null")
  end

  defn echo_value(value: {String.t() | nil, default: "foo"}) :: String.t() do
    value
  end

  defn call_echo_value() :: String.t() do
    echo_value()
  end

  defn call_echo_else() :: String.t() do
    echo_else()
  end

  defn file_name(file: {Dagger.File.t(), default_path: "dagger-module.toml"}) :: String.t() do
    Dagger.File.name(file)
  end

  defn file_names(dir: {Dagger.Directory.t(), default_path: "lib"}) :: String.t() do
    with {:ok, entries} <- Dagger.Directory.entries(dir) do
      Enum.join(entries, " ")
    end
  end

  defn files_no_ignore(dir: {Dagger.Directory.t(), default_path: "."}) :: String.t() do
    with {:ok, entries} <- Dagger.Directory.entries(dir) do
      Enum.join(entries, " ")
    end
  end

  defn files_ignore(dir: {Dagger.Directory.t(), default_path: ".", ignore: ["mix.exs"]}) :: String.t() do
    with {:ok, entries} <- Dagger.Directory.entries(dir) do
      Enum.join(entries, " ")
    end
  end

  defn files_neg_ignore(dir: {Dagger.Directory.t(), default_path: ".", ignore: ["**", "!**/*.ex"]}) :: String.t() do
    with {:ok, entries} <- Dagger.Directory.entries(dir) do
      Enum.join(entries, " ")
    end
  end

  defn echo_enum(value: BasicEnum.t() | nil) :: String.t() do
    Atom.to_string(value)
  end

  defn enum_value(value: {BasicEnum.t() | nil, default: BasicEnum.foo()}) :: String.t() do
    Atom.to_string(value)
  end

  defn echo_alias_enum(value: AliasEnum.t()) :: String.t() do
    Atom.to_string(value)
  end

  defn alias_enum_round_trip(value: AliasEnum.t()) :: AliasEnum.t() do
    value
  end

  defn alias_enum_wire_value(value: AliasEnum.t()) :: String.t() do
    AliasEnum.__enum__(:value, value)
  end

  # `high/0` is named after the key, not after the "critical" wire value.
  defn alias_enum_default(value: {AliasEnum.t() | nil, default: AliasEnum.high()}) :: String.t() do
    Atom.to_string(value)
  end
end
