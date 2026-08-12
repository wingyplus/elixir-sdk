# Elixir SDK runtime (build-only)

This is the Elixir module runtime. New Elixir modules reference it as their runtime
(`github.com/dagger/elixir-sdk/runtime`); the root Dang module (`elixir-sdk.dang`) sets it
via `targetRuntime`.

It is written in **Dang** (`main.dang`), so the engine runs its dispatch
(`moduleRuntime` / `codegen`) natively in-process — there is no runtime container for the
dispatcher itself. The actual Elixir build still runs in an `elixir:*-alpine` container.

## What it does

It only **fetches dependencies, compiles, and sets the entrypoint** for an Elixir module
from its committed sources — it does not generate code.

`moduleRuntime` mounts the module, runs `mix deps.get --only prod` → `mix deps.compile` →
`mix compile`, and returns a container whose entrypoint is
`mix dagger.entrypoint.invoke <ModuleName>`.

Modules are self-contained: the Elixir SDK is vendored as source under `<module>/dagger_sdk/`
and `mix.exs` depends on it by path, so `mix deps.get` only fetches third-party dependencies.

Before compiling, `moduleRuntime` checks that `dagger_sdk/mix.exs` exists and is non-empty,
failing early with an actionable error if `dagger generate` was never run or its output was
not committed. Without that check, `mix deps.get` fails on the unresolvable path dependency
with an error that never mentions `dagger generate`.

## What owns code generation instead

Code generation lives in this repository's root Dang module (`elixir-sdk.dang` / `mod.dang`)
and runs at `dagger generate` time. Modules commit the generated files, so the engine skips
codegen at module load and this runtime never regenerates them.

`codegen` here is an intentional no-op (it returns the module source unchanged): the SDK
runtime contract still includes it, but generation is owned by `generate`.

## Keeping names in sync

`toElixirApplicationName` / `toElixirModuleName` in `main.dang` derive the entrypoint's
module name from the Dagger module name at call time. `helpers/render-template/main.go`
derives the `defmodule` name from the same input at init time. The two implementations must
stay identical — `helpers/render-template/main_test.go` pins the cases where a
general-purpose case library would disagree (`HTTPServer`, `foo2bar`).
