# Elixir SDK runtime (build-only)

This is the Elixir module runtime. New Elixir modules reference it as their runtime
(`github.com/dagger/elixir-sdk/runtime`); the root Dang module (`elixir-sdk.dang`) sets it
via `targetRuntime`.

It is written in **Dang** (`main.dang`), so the engine runs its dispatch
(`moduleRuntime` / `codegen`) natively in-process — there is no runtime container for the
dispatcher itself. The actual Elixir build still runs in an `elixir:*-alpine` container.

## What it does

It **fetches dependencies, compiles, and sets the entrypoint** for an Elixir module.

`moduleRuntime` mounts the module, runs `mix deps.get --only prod` → `mix deps.compile` →
`mix compile`, and returns a container whose entrypoint is
`mix dagger.entrypoint.invoke <ModuleName>`.

Modules are self-contained: the Elixir SDK is vendored as source under `<module>/dagger_sdk/`
and `mix.exs` depends on it by path, so `mix deps.get` only fetches third-party dependencies.

When `dagger_sdk/mix.exs` is missing or empty — the module was scaffolded but `dagger
generate` has not run (or its output was not committed) — `moduleRuntime` builds an
equivalent `dagger_sdk/` on the fly: it vendors the SDK sources (pulled into this module's
context by the `../sdk` include patterns in `dagger.json`) and generates the API bindings
from the engine-provided introspection schema. This keeps a freshly-initialized module
loadable, which `dagger generate` itself relies on: the engine loads every workspace module
to discover generators before the SDK's `@generate` hook can write `dagger_sdk/`.

`moduleRuntime` declares `introspectionJson` as **required** on purpose. The engine skips
computing the introspection schema for runtimes that declare it optional (trusting committed
files instead); requiring it is what makes the on-the-fly fallback possible.

## What owns code generation

Code generation lives in this repository's root Dang module (`elixir-sdk.dang` / `mod.dang`)
and runs at `dagger generate` time. Modules commit the generated files; the on-the-fly path
above is only a fallback for modules that have not been generated yet, and never writes to
the workspace.

`codegen` here is an intentional no-op (it returns the module source unchanged): the SDK
runtime contract still includes it, but generation is owned by `generate`.

`vendoredSdk` / `generatedBindings` in `main.dang` are kept in step with the same functions
in `mod.dang`, which produce the committed `dagger_sdk/` at generate time.

## Keeping names in sync

`toElixirApplicationName` / `toElixirModuleName` in `main.dang` derive the entrypoint's
module name from the Dagger module name at call time. `helpers/render-template/main.go`
derives the `defmodule` name from the same input at init time. The two implementations must
stay identical — `helpers/render-template/main_test.go` pins the cases where a
general-purpose case library would disagree (`HTTPServer`, `foo2bar`).
