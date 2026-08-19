defmodule Dagger.Codegen.NamingTest do
  use ExUnit.Case, async: true

  alias Dagger.Codegen.Naming

  test "module/1" do
    assert Naming.module("Container") == "Dagger.Container"
    assert Naming.module("BuildArg") == "Dagger.BuildArg"
    assert Naming.module("SDKConfig") == "Dagger.SDKConfig"
  end

  test "module/1 exposes the GraphQL root as the client" do
    assert Naming.module("Query") == "Dagger.Client"
    assert Naming.var("Query") == "client"
  end

  test "var/1" do
    assert Naming.var("Container") == "container"
    assert Naming.var("CacheVolume") == "cache_volume"
  end

  test "function/1" do
    assert Naming.function("withEnvVariable") == "with_env_variable"
    assert Naming.function("loadSecretFromID") == "load_secret_from_id"
    assert Naming.function("experimentalWithAllGPUs") == "experimental_with_all_gpus"
  end

  test "function/1 escapes reserved words" do
    assert Naming.function("true") == "true_"
    assert Naming.function("do") == "do_"
  end

  test "function/1 spells predicates the Elixir way" do
    assert Naming.function("isTerminal") == "terminal?"
  end

  test "doc/1 rewrites API references" do
    assert Naming.doc("A simple document") == "A simple document"

    assert Naming.doc("A simple document that reference to `someFunction`") ==
             "A simple document that reference to `some_function`"
  end
end
