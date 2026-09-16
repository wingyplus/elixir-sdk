# `dagger generate` with many modules

Throwaway modules for timing `dagger generate` as a workspace grows, and the
reproduction for the cost `generatedWorkspace` in `mod.dang` avoids.

## Running it

```sh
bench/generate/sweep.sh 1 2 4 8 12 16 24     # time generate at each module count
OBJECTS=10 bench/generate/sweep.sh 8         # 8 modules, 10 objects + 10 enums each
python3 bench/generate/modules.py 12         # just create 12 modules and register them
python3 bench/generate/modules.py --clean    # remove them and their dagger.toml entries
```

The modules land in `bench/generate/mods` and are registered in `dagger.toml`
as scopes of the `elixir` SDK, which is what `dagger generate` walks. Both
are removed by `--clean`, which `sweep.sh` runs at the end; `git diff
dagger.toml` should come back empty. Each run stamps the sources with a nonce,
so the engine cannot answer from the previous run's cache.

Pick the CLI with `DAGGER`, e.g. `DAGGER="dagger --x-release 1.0.0-beta.13"`.

The time to watch is the `elixir-sdk:generate` span, which `sweep.sh` prints
per module count; the wall time around it is mostly CLI start-up and loading the
workspace's own modules, and does not grow with the module count. The engine
calls the SDK's `generateScope` once per scope and wraps the whole set in that
one span.
