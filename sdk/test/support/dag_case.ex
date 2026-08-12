defmodule Dagger.DagCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  # Cases built on this template start Dagger.Global, which connects to a live
  # engine, so tag them all :integration to keep `mix test` hermetic by default.
  using do
    quote do
      @moduletag :integration
    end
  end

  setup_all do
    start_supervised!(Dagger.Global)
    %{dag: Dagger.Global.dag()}
  end
end
