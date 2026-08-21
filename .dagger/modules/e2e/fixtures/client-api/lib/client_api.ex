defmodule ClientApi do
  @moduledoc """
  Client API checks for the Elixir SDK.

  Ported from `sdk/test/dagger/client_test.exs`, one check per test. The tests
  ran against the bindings committed in `sdk/lib/dagger/gen`; these run against
  the bindings the runtime generates from the engine's introspection schema when
  it loads this module, so they cover code generation in a real environment as
  well as the client itself.

  Assertions are pattern matches: a failed match raises `MatchError`, which
  fails the check and prints the value that did not match.
  """

  use Dagger.Mod.Object, name: "ClientApi"

  alias Dagger.BuildArg
  alias Dagger.CacheSharingMode
  alias Dagger.Client
  alias Dagger.Container
  alias Dagger.Core.ExecError
  alias Dagger.Core.QueryBuilder, as: QB
  alias Dagger.Directory
  alias Dagger.EnvVariable
  alias Dagger.File
  alias Dagger.GitRef
  alias Dagger.GitRepository
  alias Dagger.Secret
  alias Dagger.Sync

  @doc "A container runs a command and returns its stdout."
  defn container() :: Dagger.Void.t(), :check do
    {:ok, "3.20.2\n"} =
      dag()
      |> Client.container()
      |> Container.from("alpine:3.20.2")
      |> Container.with_exec(["cat", "/etc/alpine-release"])
      |> Container.stdout()

    :ok
  end

  @doc "A git repository resolves a tag and reads a file out of its tree."
  defn git_repository() :: Dagger.Void.t(), :check do
    {:ok, readme} =
      dag()
      |> Client.git("https://github.com/dagger/dagger")
      |> GitRepository.tag("v0.3.0")
      |> GitRef.tree()
      |> Directory.file("README.md")
      |> File.contents()

    ["## What is Dagger?" | _] = String.split(readme, "\n")

    :ok
  end

  @doc "A directory from a git tree builds with its Dockerfile."
  defn container_build() :: Dagger.Void.t(), :check do
    repo =
      dag()
      |> Client.git("https://github.com/dagger/dagger")
      |> GitRepository.tag("v0.3.0")
      |> GitRef.tree()

    {:ok, out} =
      repo
      |> Directory.docker_build()
      |> Container.with_exec(["dagger", "version"])
      |> Container.stdout()

    ["dagger" | _] = out |> String.trim() |> String.split(" ")

    :ok
  end

  @doc "A build takes build arguments."
  defn container_build_args() :: Dagger.Void.t(), :check do
    dockerfile = """
    FROM alpine:3.20.2
    ARG SPAM=spam
    ENV SPAM=$SPAM
    CMD printenv
    """

    {:ok, out} =
      dag()
      |> Client.directory()
      |> Directory.with_new_file("Dockerfile", dockerfile)
      |> Directory.docker_build(build_args: [%BuildArg{name: "SPAM", value: "egg"}])
      |> Container.with_exec([])
      |> Container.stdout()

    true = String.contains?(out, "SPAM=egg")

    :ok
  end

  @doc "An environment variable takes any string, including an empty one."
  defn container_with_env_variable() :: Dagger.Void.t(), :check do
    for val <- ["spam", ""] do
      {:ok, ^val} =
        dag()
        |> Client.container()
        |> Container.from("alpine:3.20.2")
        |> Container.with_env_variable("FOO", val)
        |> Container.with_exec(["sh", "-c", "echo -n $FOO"])
        |> Container.stdout()
    end

    :ok
  end

  @doc "A directory mounts into a container."
  defn container_with_mounted_directory() :: Dagger.Void.t(), :check do
    dir =
      dag()
      |> Client.directory()
      |> Directory.with_new_file("hello.txt", "Hello, world!")
      |> Directory.with_new_file("goodbye.txt", "Goodbye, world!")

    {:ok, "goodbye.txt\nhello.txt\n"} =
      dag()
      |> Client.container()
      |> Container.from("alpine:3.20.2")
      |> Container.with_mounted_directory("/mnt", dir)
      |> Container.with_exec(["ls", "/mnt"])
      |> Container.stdout()

    :ok
  end

  @doc "A mounted cache volume keeps its contents across execs."
  defn container_with_mounted_cache() :: Dagger.Void.t(), :check do
    cache_key = "example-cache-" <> Integer.to_string(Enum.random(1..1_000_000_000))
    filename = DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d-%H-%M-%S")

    container =
      dag()
      |> Client.container()
      |> Container.from("alpine:3.20.2")
      |> Container.with_mounted_cache("/cache", Client.cache_volume(dag(), cache_key),
        sharing: CacheSharingMode.locked()
      )

    out =
      for i <- 1..5 do
        container
        |> Container.with_exec([
          "sh",
          "-c",
          "echo $0 >> /cache/#{filename}.txt; cat /cache/#{filename}.txt",
          to_string(i)
        ])
        |> Container.stdout()
      end

    [
      {:ok, "1\n"},
      {:ok, "1\n2\n"},
      {:ok, "1\n2\n3\n"},
      {:ok, "1\n2\n3\n4\n"},
      {:ok, "1\n2\n3\n4\n5\n"}
    ] = out

    :ok
  end

  @doc "A directory lists the files written into it."
  defn directory() :: Dagger.Void.t(), :check do
    {:ok, ["goodbye.txt", "hello.txt"]} =
      dag()
      |> Client.directory()
      |> Directory.with_new_file("hello.txt", "Hello, world!")
      |> Directory.with_new_file("goodbye.txt", "Goodbye, world!")
      |> Directory.entries()

    :ok
  end

  @doc """
  A directory argument resolves from the module source when it is omitted.

  Stands in for the `host directory` test: a module has no host to read from,
  and `default_path` is how it reads the source it was loaded from instead.
  """
  defn default_path_directory(dir: {Dagger.Directory.t(), default_path: "."}) ::
         Dagger.Void.t(),
       :check do
    {:ok, contents} =
      dir
      |> Directory.file("mix.exs")
      |> File.contents()

    true = String.contains?(contents, "ClientApi.MixProject")

    :ok
  end

  @doc "A field returning a list of objects decodes into a list."
  defn return_list_of_objects() :: Dagger.Void.t(), :check do
    {:ok, envs} =
      dag()
      |> Client.container()
      |> Container.from("alpine:3.20.2")
      |> Container.env_variables()

    true = is_list(envs)
    [{:ok, "PATH"}] = Enum.map(envs, &EnvVariable.name/1)

    :ok
  end

  @doc "A nullable field returns nil rather than an error."
  defn nullable() :: Dagger.Void.t(), :check do
    {:ok, nil} =
      dag()
      |> Client.container()
      |> Container.from("alpine:3.20.2")
      |> Container.env_variable("NOTHING")

    :ok
  end

  @doc "A file loads back from its ID."
  defn load_file() :: Dagger.Void.t(), :check do
    {:ok, id} =
      dag()
      |> Client.directory()
      |> Directory.with_new_file("hello.txt", "Hello, world!")
      |> Directory.file("hello.txt")
      |> File.id()

    file = %Dagger.File{
      query_builder:
        QB.query()
        |> QB.select("node", id: id)
        |> QB.inline_fragment("File"),
      client: dag().client
    }

    {:ok, "Hello, world!"} = File.contents(file)

    :ok
  end

  @doc "A secret loads back from its ID."
  defn load_secret() :: Dagger.Void.t(), :check do
    {:ok, id} =
      dag()
      |> Client.set_secret("foo", "bar")
      |> Secret.id()

    secret = %Dagger.Secret{
      query_builder:
        QB.query()
        |> QB.select("node", id: id)
        |> QB.inline_fragment("Secret"),
      client: dag().client
    }

    {:ok, "bar"} = Secret.plaintext(secret)

    :ok
  end

  @doc "Sync returns the object on success and an exec error on failure."
  defn container_sync() :: Dagger.Void.t(), :check do
    container =
      dag()
      |> Client.container()
      |> Container.from("alpine:3.20.2")

    {:error, %ExecError{}} = container |> Container.with_exec(["foobar"]) |> Sync.sync()

    {:ok, %Container{} = synced} =
      container |> Container.with_exec(["echo", "spam"]) |> Sync.sync()

    {:ok, "spam\n"} = Container.stdout(synced)

    :ok
  end

  @doc "An object passed as an ID argument is resolved before the query runs."
  defn id_before_constructing_arg() :: Dagger.Void.t(), :check do
    dockerfile = """
    FROM alpine
    RUN --mount=type=secret,id=the-secret echo "hello ${THE_SECRET}"
    """

    secret = Client.set_secret(dag(), "the-secret", "abcd")

    {:ok, _} =
      dag()
      |> Client.directory()
      |> Directory.with_new_file("Dockerfile", dockerfile)
      |> Directory.docker_build(dockerfile: "Dockerfile", secrets: [secret])
      |> Sync.sync()

    container = Client.container(dag())
    %Container{} = Client.container(dag(), id: container)

    :ok
  end

  @doc "An environment variable expands references to the ones already set."
  defn env_variable_expand() :: Dagger.Void.t(), :check do
    {:ok, "C:B"} =
      dag()
      |> Client.container()
      |> Container.from("alpine:3.20.2")
      |> Container.with_env_variable("A", "B")
      |> Container.with_env_variable("A", "C:${A}", expand: true)
      |> Container.env_variable("A")

    :ok
  end

  @doc "A service binds into another container under a hostname."
  defn service_binding() :: Dagger.Void.t(), :check do
    service =
      dag()
      |> Client.container()
      |> Container.from("nginx:1.25-alpine3.18")
      |> Container.with_exposed_port(80)
      |> Container.as_service(use_entrypoint: true)

    {:ok, out} =
      dag()
      |> Client.container()
      |> Container.from("alpine:3.18")
      |> Container.with_service_binding("nginx-service", service)
      |> Container.with_exec(~w"apk add curl")
      |> Container.with_exec(~w"curl http://nginx-service")
      |> Container.stdout()

    true = out =~ ~r/Welcome to nginx/

    :ok
  end

  @doc "A string argument survives quoting, escapes and non-ASCII characters."
  defn string_escape() :: Dagger.Void.t(), :check do
    {:ok, _} =
      dag()
      |> Client.container()
      |> Container.from("nginx:1.25-alpine3.18")
      |> Container.with_new_file(
        "/a.txt",
        """
          \\  /       Partly cloudy
        _ /\"\".-.     +29(31) °C
          \\_(   ).   ↑ 13 km/h
          /(___(__)  10 km
                     0.0 mm
        """
      )
      |> Sync.sync()

    :ok
  end

  @doc "An enum field decodes into an atom."
  defn return_scalar() :: Dagger.Void.t(), :check do
    {:ok, :OBJECT_KIND} =
      dag()
      |> Client.type_def()
      |> Dagger.TypeDef.with_object("A")
      |> Dagger.TypeDef.kind()

    :ok
  end

  @doc "A failing exec reports the query path and the exit code."
  defn exec_error() :: Dagger.Void.t(), :check do
    {:error, error} =
      dag()
      |> Client.container()
      |> Container.from("alpine:3.20.2")
      |> Container.with_exec(["foobar"])
      |> Sync.sync()

    true = Exception.message(error) =~ ~r/container\.from\.withExec\.sync exit code: 1/

    :ok
  end

  @doc "Mounting a directory at the root does not crash. Regression test for #8601."
  defn with_directory() :: Dagger.Void.t(), :check do
    dir =
      dag()
      |> Client.directory()
      |> Directory.with_new_directory("/abcd")

    {:ok, ["abcd/"]} =
      dag()
      |> Client.directory()
      |> Directory.with_directory("/", dir)
      |> Directory.entries()

    :ok
  end
end
