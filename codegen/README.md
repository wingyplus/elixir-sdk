# dagger_codegen

Generates the Elixir API bindings (`lib/dagger/gen/`) from a Dagger GraphQL
introspection schema. Written in Zig 0.16; no dependencies.

```sh
zig build -Doptimize=ReleaseSafe
zig-out/bin/dagger_codegen generate --outdir <dir> --introspection <introspection.json>
```

The generator lays the Elixir code out itself, following `mix format`'s style, so
its output needs no formatter pass.

## Performance

A run over the full Dagger schema (~420 KB, 103 modules) takes under a
millisecond, process start-up included. What keeps it there:

- `src/parser.zig` reads the schema instead of `std.json`: it slices strings
  with no escapes straight out of the input, finds quotes and skips unused
  values with SIMD, and never builds a generic JSON tree.
- A scan reads only what the index needs (each type's kind, name and enum
  values) and where each type's JSON is. Each type is then parsed, analyzed,
  rendered and written on its own, on up to `--jobs` threads (default 4; a thread
  costs about as much to start as a small type costs to generate).
- Per-thread bump allocators (`src/Bump.zig`), no teardown before exit, and a
  memory-mapped input.

`dagger_codegen bench --introspection <file> [--outdir <dir>]` times each phase
in-process.

## Prebuilt image

`dagger generate` and the module runtime never build the generator. They run it
from a small image (the static executable at `/dagger_codegen`, nothing else)
pinned by digest in the `codegenImage` constant of `mod.dang` and
`runtime/main.dang`. This directory is also a Dagger module that builds and
publishes that image:

```sh
dagger call codegen publish --address <registry>/<repo>:<tag>   # linux/amd64 + linux/arm64
dagger call codegen pin --ref <the digest-pinned reference publish returned>
```

After changing the generator, publish and pin a new image, or the SDK keeps
running the previous one.

## Layout

| File | What it does |
| --- | --- |
| `src/introspection.zig` | The introspection schema, as parsed from JSON |
| `src/parser.zig` | Reads the introspection JSON, or just locates its types |
| `src/Bump.zig` | The bump allocator each run and thread allocates from |
| `src/naming.zig` | GraphQL names to Elixir names (ports of `Macro.underscore/1` and `Macro.camelize/1`) |
| `src/types.zig` | Normalized type references, typespecs, guards and encoders |
| `src/analyzer.zig` | Decides what each generated module contains |
| `src/render.zig` | Prints a module, choosing a one-line or broken layout by width |
| `src/codegen.zig` | Schema-level driver: which types get a module, where, and on which thread |
| `src/main.zig` | The `dagger_codegen` command |

## Tests

```sh
zig build test              # unit tests and snapshot tests
zig build update-snapshots  # rewrite test/snapshots after an intended output change
```

The same through Dagger: `dagger check codegen:test` (plus `codegen:image-test`,
which runs the image over the engine's schema) and `dagger call codegen
update-snapshots`.

Each snapshot case in `test/cases.zig` renders one fixture from
`test/fixtures/` and compares it byte-for-byte with `test/snapshots/`.
`zig build test --summary all` shows what ran.
