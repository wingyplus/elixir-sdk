defmodule Dagger do
  @moduledoc """
  The [Dagger](https://dagger.io/) SDK for Elixir.

  Use it to build, test, and ship your software in containers, written
  entirely in Elixir.

  ## Requirements

  Make sure `docker` and `dagger` are installed and available on your `PATH`.

  ## Getting started

  Save the script below as `hello.exs` and run it with `elixir hello.exs`:

      Mix.install([:dagger])

      {:ok, client} = Dagger.connect()

      {:ok, output} =
        client
        |> Dagger.Client.container()
        |> Dagger.Container.from("hexpm/elixir:1.14.4-erlang-25.3-debian-buster-20230227-slim")
        |> Dagger.Container.with_exec(["elixir", "--version"])
        |> Dagger.Container.stdout()

      IO.puts(output)

      Dagger.close(client)

  The script:

  1. Connects to the Dagger Engine with `connect/1`.
  2. Starts a container from an Elixir image.
  3. Runs `elixir --version` inside it and prints the output.
  4. Closes the connection with `close/1`.

  To have the connection closed for you, use `with_connection/2`:

      Dagger.with_connection(fn client ->
        client
        |> Dagger.Client.container()
        |> Dagger.Container.from("alpine")
        |> Dagger.Container.with_exec(["echo", "hello"])
        |> Dagger.Container.stdout()
      end)

  ## Using Req as the HTTP client

  The SDK uses Erlang's built-in `:httpc` by default. To use
  [Req](https://hex.pm/packages/req) instead, add `:req` to your dependencies
  and set this in `config/config.exs`:

      config :dagger, client: Dagger.Core.GraphQLClient.Req

  ## Dagger modules

  You can also write Dagger modules in Elixir. See `Dagger.Mod.Object` to
  get started.
  """

  @doc """
  Connecting to Dagger.

  When calling this function, it try to connect in order:

  1. Use session from `DAGGER_SESSION_PORT` and `DAGGER_SESSION_TOKEN` shell
     environment variables.
  2. If (1) doesn't specified, it will lookup a binary defined in `_EXPERIMENTAL_DAGGER_CLI_BIN`
     and start a session.
  3. Download the latest binary from Dagger and start a session.

  ## Options

  #{NimbleOptions.docs(Dagger.Core.Client.connect_schema())}
  """
  def connect(opts \\ []) do
    with {:ok, engine_client} <- Dagger.Core.Client.connect(opts) do
      client = %Dagger.Client{
        client: engine_client,
        query_builder: Dagger.Core.QueryBuilder.query()
      }

      {:ok, client}
    end
  end

  @doc """
  Similar to `connect/1` but raise exception when found an error.
  """
  def connect!(opts \\ []) do
    case connect(opts) do
      {:ok, query} -> query
      error -> raise "Cannot connect to Dagger engine, cause: #{inspect(error)}"
    end
  end

  @doc """
  Connect to Dagger Engine and close connection automatically after `fun` executed.

  See `connect/1` for available options.
  """
  def with_connection(fun, opts \\ []) when is_function(fun, 1) and is_list(opts) do
    with {:ok, client} <- Dagger.connect(opts) do
      try do
        fun.(client)
      after
        close(client)
      end
    end
  end

  @doc """
  Disconnecting the client from Dagger Engine session.
  """
  def close(%Dagger.Client{client: client}) do
    Dagger.Core.Client.close(client)
  end
end
