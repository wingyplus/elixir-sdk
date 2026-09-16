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
under the SDK's `as-sdk` entries, which is what `dagger generate` walks. Both
are removed by `--clean`, which `sweep.sh` runs at the end; `git diff
dagger.toml` should come back empty. Each run stamps the sources with a nonce,
so the engine cannot answer from the previous run's cache.

Pick the CLI with `DAGGER`, e.g. `DAGGER="dagger --x-release 1.0.0-beta.11"`.

## What it found

`generateAll` folds the managed modules, each generating onto the workspace the
previous one produced. `generatedWorkspace` used to read the module it was
generating *from* that same accumulating workspace, and resolving a module
source costs more the more changes are layered on the workspace it is read
from: within one run, `Workspace.moduleSource` grew from 0.1s for the first
modules to 0.8s for the last. Generating N modules cost N².

Reading each module from the workspace as it was before any module was
generated — plus its own dependency closure, which `generateLocalDependencies`
stages there — makes it linear. Time inside `elixir-sdk:generate-all`:

| modules | 1 | 2 | 4 | 8 | 12 | 16 | 24 |
|---|---|---|---|---|---|---|---|
| before | 0.3s | 0.5s | 1.0s | 2.9s | 5.0s | 8.6s | 23.1s |
| after | 0.4s | 0.4s | 0.6s | 0.9s | 1.3s | 1.7s | 2.7s |

Two things this also settled:

- **Module size does not matter.** 8 modules with 0, 5, 10 and 20 objects and
  enums each all generate in 0.6–0.7s: a module's bindings are the core API plus
  its dependencies, so its own objects and enums never enter its codegen, and
  `generate` does not load or compile the modules.
- **There is a fixed floor** of around 3.6s of wall time with no Elixir modules
  registered at all — CLI start-up, connecting, and loading the workspace's own
  modules — which does not grow with the number of modules.
