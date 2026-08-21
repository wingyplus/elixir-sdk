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

  # `:up` and `:agent` are the other two function flags. Neither is a check, so
  # neither is discovered by `dagger check`; what they exercise here is that the
  # engine accepts their shape when it loads the module.
  defn up_service() :: Dagger.Service.t(), :up do
    dag()
    |> Dagger.Client.container()
    |> Dagger.Container.from("alpine:3")
    |> Dagger.Container.with_exposed_port(8080)
    |> Dagger.Container.as_service(args: ["sh", "-c", "while true; do sleep 1; done"])
  end

  defn agent_middleware(base: Dagger.LLM.t()) :: Dagger.LLM.t(), :agent do
    Dagger.LLM.with_system_prompt(base, "be brief")
  end
end
