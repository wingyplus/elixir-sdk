# elixir-sdk

A Dagger module for managing Dagger modules that use the Elixir SDK, plus the Elixir client
library itself.

SDK-specific module authoring (scaffolding new modules, language build config, codegen)
lives in modules like this one. Under the CLI 1.0 SDK-module contract the engine drives the
SDK per *scope*: it owns the scope records and the generation graph, and calls this module's
`generateScope` once for each scope — the same call whether the module is being created or
regenerated. Shared, language-agnostic operations — editing a
module's dependencies or its required engine version — are owned by the core CLI
(`dagger module deps`, `dagger module engine`) and are not part of this module's surface.

## What's in here

| Path | What it is |
| --- | --- |
| `elixir-sdk.dang`, `mod.dang`, `template.dang` | The SDK contract module — `findClientRoot`, `generateScope`, and `targetRuntime` |
| `runtime/` | The module runtime new Elixir modules reference. Build-only; see [its README](./runtime/README.md) |
| `sdk/` | The Elixir client library (`dagger` on Hex) |
| `codegen/` | The code generator, written in Zig, and the module that tests and publishes it as a prebuilt image. See [its README](./codegen/README.md) |
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

`dagger module init` registers the scope and then calls `generateScope`, which seeds the
template, writes `dagger-module.toml`, and vendors the SDK in one step — so the module
compiles straight away. The explicit `dagger generate` above is only needed to pick up later
schema changes.

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
engine's schema, into `<module source>/dagger_sdk/` — next to the `mix.exs` that depends on
it, which is the module's source directory rather than the directory holding its config when
the two differ. **Commit it** — the runtime builds from the committed sources and never
regenerates them.

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

After an intended change to the generated code, rewrite the code generator's snapshots and
review the changeset:

```sh
dagger call -m .dagger/modules/dev update-codegen-tests
```

Check the SDK against the shared contract suite:

```sh
dagger -m github.com/dagger/sdk-sdk -W . check
```

> **Note:** `sdk-sdk` has not been updated for the CLI 1.0 SDK-module interface. It still
> checks the superseded `initModule` + `@generate` contract against a pinned v1.0.0-beta.10
> CLI, and one of its assertions — that an SDK never writes `dagger-module.toml` — is the
> opposite of what `generateScope` is now required to do. The suite does not pass against
> this SDK until it is ported upstream.

`sdk/`'s test suite is hermetic by default; tests that need a live engine are tagged
`:integration` and run with `mix test --include integration`.

See [`elixir-sdk.dang`](./elixir-sdk.dang) for the full type surface.
