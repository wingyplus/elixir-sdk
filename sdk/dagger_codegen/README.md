# dagger_codegen

Generates the Elixir API bindings (`lib/dagger/gen/`) from a Dagger GraphQL
introspection schema. Written in Zig 0.16; no dependencies.

```sh
zig build -Doptimize=ReleaseSafe
zig-out/bin/dagger_codegen generate --outdir <dir> --introspection <introspection.json>
```

The generator lays the Elixir code out itself, following `mix format`'s style, so
its output needs no formatter pass. `dagger generate` and the module runtime
build it in a container; see `generatedBindings` in `mod.dang` and
`runtime/main.dang`.

## Layout

| File | What it does |
| --- | --- |
| `src/introspection.zig` | The introspection schema, as parsed from JSON |
| `src/naming.zig` | GraphQL names to Elixir names (ports of `Macro.underscore/1` and `Macro.camelize/1`) |
| `src/types.zig` | Normalized type references, typespecs, guards and encoders |
| `src/analyzer.zig` | Decides what each generated module contains |
| `src/render.zig` | Prints a module, choosing a one-line or broken layout by width |
| `src/codegen.zig` | Schema-level driver: which types get a module, and where |
| `src/main.zig` | The `dagger_codegen` command |

## Tests

```sh
zig build test              # unit tests and snapshot tests
zig build update-snapshots  # rewrite test/snapshots after an intended output change
```

Each snapshot case in `test/cases.zig` renders one fixture from
`test/fixtures/` and compares it byte-for-byte with `test/snapshots/`.
`zig build test --summary all` shows what ran.
