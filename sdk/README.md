> **Warning** This SDK is experimental. Please do not use it for anything
> mission-critical. Possible issues include:

- Missing features
- Stability issues
- Performance issues
- Lack of polish
- Upcoming breaking changes
- Incomplete or out-of-date documentation

# Dagger

[Dagger](https://dagger.io) SDK for Elixir.

## Installation

Fetch from repository by:

```elixir
def deps do
  [
    {:dagger, github: "dagger/elixir-sdk", sparse: "sdk"}
  ]
end
```

## Running

Let's write a code below into a script:

```elixir
# ci.exs
client = Dagger.connect!()

{:ok, out} =
  client
  |> Dagger.Client.container([])
  |> Dagger.Container.from("hexpm/elixir:1.14.4-erlang-25.3-debian-buster-20230227-slim")
  |> Dagger.Container.with_exec(["elixir", "--version"])
  |> Dagger.Container.stdout()

IO.puts(out)

Dagger.close(client)
```

Then running with:

```shell
elixir ci.exs
```

Where `ci.exs` contains Elixir script above.

## Using with Dagger Functions

This directory is the client library. The Dagger module tooling that scaffolds and
generates Elixir modules lives at the root of this repository — see the [top-level
README](../README.md).

In short:

```shell
dagger sdk install github.com/dagger/elixir-sdk
dagger module init elixir <name>
dagger generate
```

`dagger generate` vendors this library, plus the API bindings generated from your engine's
schema, into `<name>/dagger_sdk/`. Your module's `mix.exs` depends on it by path:

```elixir
defp deps do
  [
    {:dagger, path: "./dagger_sdk"}
  ]
end
```
