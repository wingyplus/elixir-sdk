# Tests tagged :integration connect to a live Dagger engine (they call
# Dagger.connect!/1, directly or via Dagger.DagCase). They are excluded by
# default so `mix test` is hermetic; run them with:
#
#     mix test --include integration
#
# The dev module's `sdk-test` check does exactly that, inside a container that
# has a Dagger client available.
ExUnit.start(exclude: [:integration])
