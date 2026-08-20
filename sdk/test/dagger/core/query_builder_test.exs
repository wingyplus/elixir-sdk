defmodule Dagger.Core.QueryBuilderTest do
  use ExUnit.Case, async: true

  alias Dagger.Core.QueryBuilder, as: QB

  describe "build/1" do
    test "select without arguments" do
      q =
        QB.query()
        |> QB.select("container")
        |> QB.select("stdout")
        |> QB.build()

      assert q == "query{container{stdout}}"
    end

    test "encode atom to enum" do
      q =
        QB.query()
        |> QB.select("container")
        |> QB.select("withExposedPort", protocol: :TCP)
        |> QB.build()

      assert q == "query{container{withExposedPort(protocol:TCP)}}"
    end

    test "encode scalars" do
      assert build_arg(:path, "/app") == ~s|query{container(path:"/app")}|
      assert build_arg(:port, 8080) == "query{container(port:8080)}"
      assert build_arg(:expand, true) == "query{container(expand:true)}"
      assert build_arg(:expand, false) == "query{container(expand:false)}"
      assert build_arg(:args, ["echo", "hello"]) == ~s|query{container(args:["echo","hello"])}|
    end

    test "accept a binary argument name" do
      assert build_arg("path", "/app") == ~s|query{container(path:"/app")}|
    end

    test "keep the arguments in the order they were given" do
      q =
        QB.query()
        |> QB.select("container")
        |> QB.select("withEnvVariable", name: "PATH", value: "/bin", expand: true)
        |> QB.build()

      assert q == ~s|query{container{withEnvVariable(name:"PATH",value:"/bin",expand:true)}}|
    end

    test "skip the argument that its value is nil" do
      assert build_arg(:expand, nil) == "query{container}"

      q =
        QB.query()
        |> QB.select("container", path: "/app", expand: nil, port: 8080)
        |> QB.build()

      assert q == ~s|query{container(path:"/app",port:8080)}|
    end

    test "encode a nested nil to null" do
      assert build_arg(:args, ["echo", nil]) == ~s|query{container(args:["echo",null])}|
    end

    test "escape a string" do
      assert build_arg(:s, ~S|a "quoted" \ value|) ==
               ~S|query{container(s:"a \"quoted\" \\ value")}|

      assert build_arg(:s, "line\r\nsep\ttab") == ~S|query{container(s:"line\r\nsep\ttab")}|

      assert build_arg(:s, "form\ffeed\bback") == ~S|query{container(s:"form\ffeed\bback")}|

      assert build_arg(:s, <<"null:", 0, ",bell:", 7>>) ==
               ~S|query{container(s:"null:\u0000,bell:\u0007")}|

      assert build_arg(:s, "héllo → 🐳") == ~s|query{container(s:"héllo → 🐳")}|
    end

    test "encode an input object with the schema field names" do
      block = %Dagger.LLMContentBlockInput{kind: :TOOL_CALL, call_id: "1", tool_name: "read"}

      assert build_arg(:block, block) ==
               ~S|query{container(block:{callId:"1",kind:TOOL_CALL,toolName:"read"})}|
    end

    test "encode an input object without its unset fields" do
      assert build_arg(:port, %Dagger.PortForward{backend: 8080}) ==
               "query{container(port:{backend:8080})}"

      assert build_arg(:ports, [
               %Dagger.PortForward{backend: 8080, frontend: 80, protocol: :TCP},
               %Dagger.PortForward{backend: 9090}
             ]) ==
               "query{container(ports:[{backend:8080,frontend:80,protocol:TCP},{backend:9090}])}"
    end

    test "encode a map like an input object" do
      assert build_arg(:port, %{backend: 8080, protocol: nil}) ==
               "query{container(port:{backend:8080})}"
    end

    test "select an inline fragment" do
      q =
        QB.query()
        |> QB.select("node", id: "abc")
        |> QB.inline_fragment("Container")
        |> QB.select("stdout")
        |> QB.build()

      assert q == ~s|query{node(id:"abc"){... on Container{stdout}}}|
    end
  end

  describe "select_fields/2" do
    test "select a set of leaf fields" do
      q =
        QB.query()
        |> QB.select("container")
        |> QB.select("envVariables")
        |> QB.select_fields(["id", "name", "value"])
        |> QB.build()

      assert q == "query{container{envVariables{id name value}}}"
    end

    test "select a single leaf field" do
      q =
        QB.query()
        |> QB.select("container")
        |> QB.select("envVariables")
        |> QB.select_fields(["id"])
        |> QB.build()

      assert q == "query{container{envVariables{id}}}"
    end

    test "a leaf field set ends the query" do
      q = QB.query() |> QB.select("container") |> QB.select_fields(["stdout", "stderr"])

      assert_raise ArgumentError, ~r/a query ends there/, fn -> QB.select(q, "stdout") end
      assert_raise ArgumentError, ~r/a query ends there/, fn -> QB.select_fields(q, ["id"]) end
      assert_raise ArgumentError, ~r/a query ends there/, fn -> QB.inline_fragment(q, "File") end
    end
  end

  describe "path/1" do
    test "return the selected field names, ignoring inline fragments" do
      q =
        QB.query()
        |> QB.select("node", id: "abc")
        |> QB.inline_fragment("Container")
        |> QB.select("stdout")

      assert QB.path(q) == ["node", "stdout"]
    end

    test "stop above a leaf field set" do
      q =
        QB.query()
        |> QB.select("container")
        |> QB.select("envVariables")
        |> QB.select_fields(["id", "name"])

      assert QB.path(q) == ["container", "envVariables"]
    end
  end

  describe "build/1 with a long string" do
    test "escape at every offset of a string spanning many runs" do
      pieces = [
        {"plain ascii text", "plain ascii text"},
        {~s|"|, ~S|\"|},
        {"a", "a"},
        {"\n", ~S|\n|},
        {"a longer run of ordinary bytes, to shift the following offsets",
         "a longer run of ordinary bytes, to shift the following offsets"},
        {<<7>>, ~S|\u0007|},
        {"héllo \u{1F433}", "héllo \u{1F433}"},
        {"\\", ~S|\\|}
      ]

      {input, escaped} =
        Enum.reduce(1..2_000, {[], []}, fn _, {input, escaped} ->
          {[input | Enum.map(pieces, &elem(&1, 0))], [escaped | Enum.map(pieces, &elem(&1, 1))]}
        end)

      input = IO.iodata_to_binary(input)
      escaped = IO.iodata_to_binary(escaped)

      assert byte_size(input) > 100_000
      assert build_arg(:s, input) == ~s|query{container(s:"#{escaped}")}|
    end
  end

  defp build_arg(name, value) do
    QB.query()
    |> QB.select("container", [{name, value}])
    |> QB.build()
  end
end
