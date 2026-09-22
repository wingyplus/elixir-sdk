defmodule Dagger.Core.GraphQLClient.HttpcTest do
  use ExUnit.Case, async: true

  alias Dagger.Core.EngineConn
  alias Dagger.Core.GraphQLClient.Httpc

  # Connects to a live engine in setup_all.
  @moduletag :integration

  setup_all do
    dag = Dagger.connect!(connect_timeout: :timer.seconds(60))
    on_exit(fn -> Dagger.close(dag) end)

    %{dag: dag}
  end

  setup %{dag: dag} do
    token = Base.encode64(EngineConn.token(dag.client.conn) <> ":")
    %{url: dag.client.url, headers: [{"authorization", "Basic " <> token}]}
  end

  test "return the response body as a binary", %{url: url, headers: headers} do
    body = Jason.encode!(%{query: "query{version}", variables: %{}})

    assert {:ok, 200, response} = Httpc.request(url, body, headers, [])
    assert is_binary(response)
    assert %{"data" => %{"version" => _}} = Jason.decode!(response)
  end

  test "queue no request behind another one", %{url: url, headers: headers} do
    body = Jason.encode!(%{query: "query{version}", variables: %{}})
    {:ok, 200, _} = Httpc.request(url, body, headers, [])

    assert {:ok, options} =
             :httpc.get_options([:max_sessions, :max_keep_alive_length], :dagger_sdk)

    assert options[:max_keep_alive_length] == 0
    assert options[:max_sessions] > 2
  end
end
