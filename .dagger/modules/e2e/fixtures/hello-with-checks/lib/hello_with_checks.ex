defmodule HelloWithChecks do
  @moduledoc false

  use Dagger.Mod.Object, name: "HelloWithChecks"

  defn passing_check() :: Dagger.Void.t(), :check do
    :ok
  end

  defn failing_check() :: Dagger.Void.t(), :check do
    raise "this check always fails"
  end

  defn passing_container() :: Dagger.Container.t(), :check do
    dag()
    |> Dagger.Client.container()
    |> Dagger.Container.from("alpine:3")
    |> Dagger.Container.with_exec(["sh", "-c", "exit 0"])
  end

  defn failing_container() :: Dagger.Container.t(), :check do
    dag()
    |> Dagger.Client.container()
    |> Dagger.Container.from("alpine:3")
    |> Dagger.Container.with_exec(["sh", "-c", "exit 1"])
  end
end
