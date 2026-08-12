# elixir-sdk

A Dagger module for managing Dagger modules that use the Elixir SDK, plus the Elixir client
library itself.

SDK-specific module authoring (scaffolding new modules, language build config, codegen)
lives in modules like this one. Under the CLI 1.0 init contract the engine drives the SDK:
this module exposes `initModule` and `targetRuntime`, and the engine merges the SDK-owned
files with its own workspace bookkeeping. Shared, language-agnostic operations — editing a
module's dependencies or its required engine version — are owned by the core CLI
(`dagger module deps`, `dagger module engine`) and are not part of this module's surface.

Backed by [`github.com/dagger/polyfill`](https://github.com/dagger/polyfill).

## What's in here

| Path | What it is |
| --- | --- |
| `elixir-sdk.dang`, `mod.dang`, `template.dang` | The SDK contract module — `initModule`, `targetRuntime`, and the `@generate` hook |
| `runtime/` | The module runtime new Elixir modules reference. Build-only; see [its README](./runtime/README.md) |
| `sdk/` | The Elixir client library (`dagger` on Hex) and its codegen project |
| `templates/` | Starter templates for `dagger module init elixir` |
| `helpers/render-template/` | Go helper that renders a template for a given module name |
| `.dagger/modules/dev/` | Lint and test tooling for `sdk/` |

## Install

From your workspace root:

```sh
dagger sdk install github.com/dagger/elixir-sdk
```

After install, the module is available in `dagger call` as `elixir-sdk`.

Calls that return a `Changeset` will print the diff and prompt you to confirm before writing
anything to your workspace.

## Create a new module

```sh
dagger module init elixir my-module
dagger generate
```

`initModule` only seeds the SDK-owned template files; the engine writes the module config
and workspace entries. **Run `generate` afterwards** — a fresh module's `mix.exs` depends on
`./dagger_sdk`, which generation writes, so it does not compile until then.

Pick a starter with `--template`:

```sh
dagger module init elixir my-module --template empty
```

`default` (the default) gives you a working module with two example functions; `empty` gives
you a bare object module.

You can also call the function directly for testing. `path` is required (the engine supplies
it in the dispatched path):

```sh
dagger call elixir-sdk init-module --name my-module --path .dagger/modules/my-module
```

## Generate SDK files

For a single module:

```sh
dagger call elixir-sdk mod --path my-module generate
```

For every Elixir SDK module visible from your current directory:

```sh
dagger generate
```

Generation vendors the Elixir SDK, together with the API bindings generated from your
engine's schema, into `<module>/dagger_sdk/`. **Commit it** — the runtime builds from the
committed sources and never regenerates them.

To exclude a directory tree from bulk generation, drop an empty
`.dagger-elixir-sdk-skip-generate` file at or above the module root:

```sh
touch some/fixture/.dagger-elixir-sdk-skip-generate
```

## Manage dependencies and the engine version

Editing a module's dependencies or its required engine version is identical across SDKs, so
the core CLI owns it:

```sh
dagger module deps add github.com/some/module
dagger module engine require-latest
```

## Develop this repository

```sh
dagger call -m .dagger/modules/dev lint
dagger call -m .dagger/modules/dev sdk-test
dagger call -m .dagger/modules/dev codegen-test
```

Check the SDK against the shared contract suite:

```sh
dagger -m github.com/dagger/sdk-sdk -W . check
```

`sdk/`'s test suite is hermetic by default; tests that need a live engine are tagged
`:integration` and run with `mix test --include integration`.

See [`elixir-sdk.dang`](./elixir-sdk.dang) for the full type surface.
