# Elixir SDK runtime (build-only)

This is the Elixir module runtime. New Elixir modules reference it as their runtime
(`github.com/dagger/elixir-sdk/runtime`); the root Dang module (`elixir-sdk.dang`) sets it
via `targetRuntime`.

It is written in **Dang** (`main.dang`), so the engine runs its dispatch
(`moduleRuntime` / `codegen`) natively in-process — there is no runtime container for the
dispatcher itself. The actual Elixir build still runs in an `elixir:*-alpine` container.

## What it does

It **fetches dependencies, compiles, and sets the entrypoint** for an Elixir module.

`moduleRuntime` mounts the module and runs `mix do deps.get --only prod + compile` in one Mix
VM. `deps` and `_build` live on a cache volume for the module (keyed by its host path for a
local source, by its commit for a remote one), so a rebuild after an edit compiles only what
Mix finds stale — usually the module's own changed files, not the vendored SDK. The compiled
applications are then copied out of the volume.

Calls do not go through Mix. The entrypoint starts `elixir` with the compiled applications on
the code path, applies the module's `config/config.exs`, and calls `Dagger.Mod.invoke/1`,
which is what the SDK's `dagger.entrypoint.invoke` Mix task does. That is one VM instead of
two and no compile check: about 140ms to start instead of 510ms, for the registration call and
for every function call. (A release starts as fast, but strips the documentation chunks the
SDK reads function descriptions from.)

Modules are self-contained: the Elixir SDK is vendored as source under `<module>/dagger_sdk/`
and `mix.exs` depends on it by path, so `mix deps.get` only fetches third-party dependencies.

When `dagger_sdk/mix.exs` is missing or empty — the module was scaffolded but `dagger
generate` has not run (or its output was not committed) — `moduleRuntime` builds an
equivalent `dagger_sdk/` on the fly: it vendors the SDK sources (pulled into this module's
context by the `../sdk` include patterns in `dagger-module.toml`) and generates the API bindings
from the engine-provided introspection schema. This keeps a freshly-initialized module
loadable, which `dagger generate` itself relies on: the engine has to load a module to read
the schema it generates against, and for a new module that happens before `generateScope`
has written `dagger_sdk/`.

`moduleRuntime` declares `introspectionJson` as **required** on purpose. The engine skips
computing the introspection schema for runtimes that declare it optional (trusting committed
files instead); requiring it is what makes the on-the-fly fallback possible.

## What owns code generation

Code generation lives in this repository's root Dang module (`elixir-sdk.dang` / `mod.dang`)
and runs when the engine calls the SDK's `generateScope` — during `dagger module init` and
again on `dagger generate`. Modules commit the generated files; the on-the-fly path above is
only a fallback for modules that have not been generated yet, and never writes to the
workspace.

`codegen` here is an intentional no-op (it returns the module source unchanged): the module
*runtime* contract still includes it, but generation is owned by the SDK module's
`generateScope`. The two are separate contracts — this directory implements the runtime that
loads an Elixir module, while `elixir-sdk.dang` implements the workspace SDK module.

`vendoredSdk` / `generatedBindings` in `main.dang` are kept in step with the same functions
in `mod.dang`, which produce the committed `dagger_sdk/` at generate time.

## Keeping names in sync

`toElixirApplicationName` / `toElixirModuleName` in `main.dang` derive the entrypoint's
module name from the Dagger module name at call time. `helpers/render-template/main.go`
derives the `defmodule` name from the same input at init time. The two implementations must
stay identical — `helpers/render-template/main_test.go` pins the cases where a
general-purpose case library would disagree (`HTTPServer`, `foo2bar`).
