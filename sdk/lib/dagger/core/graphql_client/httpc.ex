defmodule Dagger.Core.GraphQLClient.Httpc do
  @moduledoc """
  `:httpc` HTTP adapter for GraphQL client.

  Requests go through an `:httpc` profile of the SDK's own, so that the
  settings below do not change the default profile the application may be
  using.
  """

  @behaviour Dagger.Core.GraphQLClient

  @profile :dagger_sdk

  # The default profile keeps two connections to a host and queues any further
  # request behind one still running on them, so queries sent concurrently -
  # from `Task.async/1`, say - ran one after another, a quick one waiting out
  # a long `withExec`. Queueing nothing lets every request start at once, and
  # the larger session limit lets those requests reuse connections instead of
  # opening a throwaway one each.
  @profile_options [max_sessions: 64, max_keep_alive_length: 0]

  @impl true
  def request(url, request_body, headers, http_opts) do
    headers = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), v} end)
    content_type = ~c"application/json"
    request = {url, headers, content_type, request_body}

    # The body is otherwise returned as a charlist, which takes 16 bytes of
    # memory per byte of the response and is slower to decode.
    options = [body_format: :binary]

    case send_request(request, http_opts, options) do
      {:ok, {{_, status_code, _}, _, response}} ->
        {:ok, status_code, response}

      otherwise ->
        otherwise
    end
  end

  # The profile is started by the first request that finds it missing.
  defp send_request(request, http_opts, options) do
    :httpc.request(:post, request, http_opts, options, @profile)
  catch
    :exit, {:noproc, _} ->
      :ok = start_profile()
      :httpc.request(:post, request, http_opts, options, @profile)
  end

  defp start_profile() do
    case :inets.start(:httpc, profile: @profile) do
      {:ok, _pid} -> :httpc.set_options(@profile_options, @profile)
      # Another request started it first, and sets the options itself.
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end
  end
end
