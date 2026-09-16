#!/usr/bin/env python3
"""Create throwaway Elixir SDK modules in this workspace, to time `dagger generate`.

    python3 bench/generate/modules.py 12          # 12 modules
    python3 bench/generate/modules.py 8 --objects 10   # ...with 10 objects + 10 enums each
    python3 bench/generate/modules.py --clean     # remove them again

The modules land in bench/generate/mods (git-ignored) and are registered in
dagger.toml as scopes of the elixir SDK, which is what `dagger generate` walks.
`--clean` removes both. Every run stamps the sources with a nonce, so the engine
cannot answer from a previous run's cache.
"""
import argparse, os, re, shutil, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODS = os.path.join(ROOT, "bench", "generate", "mods")
TOML = os.path.join(ROOT, "dagger.toml")
ENTRY = re.compile(r'\n\[sdks\.elixir\.scopes\."bench/generate/mods/[^"]*"\]\nis-module = true\n')

MIX = '''defmodule {mod}.MixProject do
  use Mix.Project

  def project do
    [app: :{app}, version: "0.1.0", elixir: "~> 1.17", deps: deps()]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [{{:dagger, path: "./dagger_sdk"}}]
  end
end
'''

CONFIG = '''name = "{name}"
engineVersion = "v1.0.0-beta.11"

[runtime]
  source = "../../../../runtime"
'''

OBJECT = '''defmodule {mod}.O{j} do
  @moduledoc """
  Object {j} of {mod}. {nonce}
  """

  use Dagger.Mod.Object, name: "{mod}O{j}"

  object do
    field :label, String.t()
  end

  @doc """
  A function on object {j}.
  """
  defn describe(prefix: String.t()) :: String.t() do
    prefix <> "-o{j}"
  end
end
'''

ENUM = '''defmodule {mod}.E{j} do
  @moduledoc """
  Enum {j} of {mod}. {nonce}
  """

  use Dagger.Mod.Enum, name: "{mod}E{j}", values: [ALPHA: "ALPHA", BETA: "BETA", GAMMA: "GAMMA"]
end
'''

ROOT_FN = '''
  @doc """
  Return object {j}.
  """
  defn object{j}() :: {mod}.O{j}.t() do
    %{mod}.O{j}{{label: "o{j}"}}
  end

  @doc """
  Echo enum {j}.
  """
  defn enum{j}(value: {mod}.E{j}.t()) :: {mod}.E{j}.t() do
    value
  end'''

MAIN = '''defmodule {mod} do
  @moduledoc """
  Throwaway module {mod}, with {objects} objects and {objects} enums. {nonce}
  """

  use Dagger.Mod.Object, name: "{mod}"

  @doc """
  Echo a string.
  """
  defn echo(value: String.t()) :: String.t() do
    value
  end
{functions}
end
'''


def register(paths):
    text = ENTRY.sub("\n", open(TOML).read()).rstrip("\n") + "\n"
    text += "".join(
        f'\n[sdks.elixir.scopes."{p}"]\nis-module = true\n' for p in paths
    )
    open(TOML, "w").write(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("modules", nargs="?", type=int, default=0, help="how many modules to create")
    parser.add_argument("--objects", type=int, default=0, help="objects and enums per module")
    parser.add_argument("--clean", action="store_true", help="remove the modules and their entries")
    args = parser.parse_args()

    shutil.rmtree(MODS, ignore_errors=True)
    if args.clean:
        register([])
        print("removed bench/generate/mods and its dagger.toml entries")
        return

    nonce = str(time.time_ns())
    paths = []
    for i in range(1, args.modules + 1):
        name, mod, app = f"m{i}", f"M{i}", f"m{i}"
        directory = os.path.join(MODS, name)
        os.makedirs(os.path.join(directory, "lib", app))
        open(os.path.join(directory, "mix.exs"), "w").write(MIX.format(mod=mod, app=app))
        open(os.path.join(directory, "dagger-module.toml"), "w").write(CONFIG.format(name=name))
        for j in range(1, args.objects + 1):
            open(os.path.join(directory, "lib", app, f"o{j}.ex"), "w").write(OBJECT.format(mod=mod, j=j, nonce=nonce))
            open(os.path.join(directory, "lib", app, f"e{j}.ex"), "w").write(ENUM.format(mod=mod, j=j, nonce=nonce))
        functions = "".join(ROOT_FN.format(mod=mod, j=j) for j in range(1, args.objects + 1))
        open(os.path.join(directory, "lib", f"{app}.ex"), "w").write(
            MAIN.format(mod=mod, objects=args.objects, nonce=nonce, functions=functions)
        )
        paths.append(f"bench/generate/mods/{name}")

    register(paths)
    print(f"{args.modules} modules with {args.objects} objects + {args.objects} enums each")


if __name__ == "__main__":
    main()
