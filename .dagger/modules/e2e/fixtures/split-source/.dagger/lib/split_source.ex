defmodule SplitSource do
  @moduledoc false

  use Dagger.Mod.Object, name: "SplitSource"

  defn hello() :: String.t() do
    "hello from a split-source module"
  end
end
