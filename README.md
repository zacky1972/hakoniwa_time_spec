# HakoniwaTimeSpec

Formal specification support for Hakoniwa time synchronization.

## Lean proof check

This repository contains a first Lean ideal model under `lean/`.

```bash
mix deps.get
mix test
```

`mix test` starts a LeanLsp runtime and runs:

```bash
cd lean
lake build HakoniwaTimeSpec
```

The runtime is selected by `HAKONIWA_TIME_SPEC_LEAN_RUNTIME`:

- `local` (default): run `lake` on the host through `LeanLsp.Runtime.Local`.
- `docker`: run `lake` in Docker through `LeanLsp.Runtime.Docker`.
- `auto`: use a local `lake` executable if found, otherwise use Docker.

For Docker runs, the default image is `leanprovercommunity/lean4:latest`.
Override it with `HAKONIWA_TIME_SPEC_LEAN_DOCKER_IMAGE` when a pinned image is required.

## Installation

If available in Hex, the package can be installed by adding `hakoniwa_time_spec` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hakoniwa_time_spec, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with ExDoc and published on HexDocs.
