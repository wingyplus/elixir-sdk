defmodule Dagger.Core.QueryBuilderTest do
  use ExUnit.Case, async: true

  alias Dagger.Core.QueryBuilder, as: QB

  describe "build/1" do
    test "encode atom to enum" do
      q =
        QB.query()
        |> QB.select("container")
        |> QB.select("withExposedPort")
        |> QB.put_arg("protocol", :TCP)
        |> QB.build()

      assert q == "query{container{withExposedPort(protocol:TCP)}}"
    end

    test "encode scalars" do
      assert build_arg("path", "/app") == ~s|query{container(path:"/app")}|
      assert build_arg("port", 8080) == "query{container(port:8080)}"
      assert build_arg("expand", true) == "query{container(expand:true)}"
      assert build_arg("expand", false) == "query{container(expand:false)}"
      assert build_arg("args", ["echo", "hello"]) == ~s|query{container(args:["echo","hello"])}|
    end

    test "encode nil to null" do
      assert build_arg("expand", nil) == "query{container(expand:null)}"
    end

    test "skip the argument that its value is nil" do
      q =
        QB.query()
        |> QB.select("container")
        |> QB.maybe_put_arg("expand", nil)
        |> QB.build()

      assert q == "query{container}"
    end

    test "escape a string" do
      assert build_arg("s", ~S|a "quoted" \ value|) ==
               ~S|query{container(s:"a \"quoted\" \\ value")}|

      assert build_arg("s", "line\r\nsep\ttab") == ~S|query{container(s:"line\r\nsep\ttab")}|

      assert build_arg("s", "form\ffeed\bback") == ~S|query{container(s:"form\ffeed\bback")}|

      assert build_arg("s", <<"null:", 0, ",bell:", 7>>) ==
               ~S|query{container(s:"null:\u0000,bell:\u0007")}|

      assert build_arg("s", "héllo → 🐳") == ~s|query{container(s:"héllo → 🐳")}|
    end

    test "encode an input object with the schema field names" do
      block = %Dagger.LLMContentBlockInput{kind: :TOOL_CALL, call_id: "1", tool_name: "read"}

      assert build_arg("block", block) ==
               ~S|query{container(block:{callId:"1",kind:TOOL_CALL,toolName:"read"})}|
    end

    test "encode an input object without its unset fields" do
      assert build_arg("port", %Dagger.PortForward{backend: 8080}) ==
               "query{container(port:{backend:8080})}"

      assert build_arg("ports", [
               %Dagger.PortForward{backend: 8080, frontend: 80, protocol: :TCP},
               %Dagger.PortForward{backend: 9090}
             ]) ==
               "query{container(ports:[{backend:8080,frontend:80,protocol:TCP},{backend:9090}])}"
    end

    test "encode a map like an input object" do
      assert build_arg("port", %{backend: 8080, protocol: nil}) ==
               "query{container(port:{backend:8080})}"
    end

    test "select with alias" do
      q =
        QB.query()
        |> QB.select("container")
        |> QB.select_with_alias("a", "from")
        |> QB.put_arg("address", "alpine")
        |> QB.build()

      assert q == ~s|query{container{a:from(address:"alpine")}}|
    end

    test "select an inline fragment" do
      q =
        QB.query()
        |> QB.select("node")
        |> QB.put_arg("id", "abc")
        |> QB.inline_fragment("Container")
        |> QB.select("stdout")
        |> QB.build()

      assert q == ~s|query{node(id:"abc"){... on Container{stdout}}}|
    end
  end

  describe "path/1" do
    test "return the selected field names, ignoring inline fragments" do
      q =
        QB.query()
        |> QB.select("node")
        |> QB.put_arg("id", "abc")
        |> QB.inline_fragment("Container")
        |> QB.select("stdout")

      assert QB.path(q) == ["node", "stdout"]
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
        {"h\u00e9llo \u{1F433}", "h\u00e9llo \u{1F433}"},
        {"\\", ~S|\\|}
      ]

      {input, escaped} =
        Enum.reduce(1..2_000, {[], []}, fn _, {input, escaped} ->
          {[input | Enum.map(pieces, &elem(&1, 0))], [escaped | Enum.map(pieces, &elem(&1, 1))]}
        end)

      input = IO.iodata_to_binary(input)
      escaped = IO.iodata_to_binary(escaped)

      assert byte_size(input) > 100_000
      assert build_arg("s", input) == ~s|query{container(s:"#{escaped}")}|
    end
  end

  defp build_arg(name, value) do
    QB.query()
    |> QB.select("container")
    |> QB.put_arg(name, value)
    |> QB.build()
  end
end
