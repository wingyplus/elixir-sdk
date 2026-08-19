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
  end

  test "function/1 keeps a pluralised acronym in one piece" do
    # Without this, `Macro.underscore/1` yields "experimental_with_all_gp_us".
    # See dagger/dagger#6310, which the Python SDK still has.
    assert Naming.function("experimentalWithAllGPUs") == "experimental_with_all_gpus"
    assert Naming.function("listIDs") == "list_ids"
  end

  test "function/1 leaves an acronym followed by a word alone" do
    assert Naming.function("withVCSGeneratedPaths") == "with_vcs_generated_paths"
    assert Naming.function("asHTTPState") == "as_http_state"
    assert Naming.function("withMCPServer") == "with_mcp_server"
    assert Naming.function("insecureSkipTLSVerify") == "insecure_skip_tls_verify"
    assert Naming.function("experimentalWithGPU") == "experimental_with_gpu"
  end

  test "module/1 keeps the schema's own casing, as every other SDK does" do
    assert Naming.module("SDKConfig") == "Dagger.SDKConfig"
    assert Naming.module("LLMTokenUsage") == "Dagger.LLMTokenUsage"
    assert Naming.module("HTTPState") == "Dagger.HTTPState"
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
