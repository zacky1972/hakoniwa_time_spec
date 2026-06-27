defmodule HakoniwaTimeSpecTest do
  use ExUnit.Case, async: false

  @build_timeout 180_000
  @container_workspace_root "/workspace"

  test "Lean integer-tick ideal model builds and checks proofs through LeanLsp" do
    source_lean_dir = Path.expand("../lean", __DIR__)

    assert File.exists?(Path.join(source_lean_dir, "lakefile.toml"))
    assert File.exists?(Path.join([source_lean_dir, "HakoniwaTimeSpec", "IdealModel.lean"]))

    work_lean_dir = fresh_lean_workdir()
    File.cp_r!(source_lean_dir, work_lean_dir)

    try do
      {runtime_module, runtime_options, exec_options} = lean_runtime(work_lean_dir)

      case LeanLsp.start_runtime(runtime_options) do
        {:ok, runtime} ->
          try do
            assert_lake_build(runtime_module, runtime, exec_options)
          after
            _ = runtime_module.stop(runtime)
          end

        {:error, reason} ->
          flunk("""
          Could not start LeanLsp runtime.

          Runtime: #{inspect(runtime_module)}
          Reason: #{inspect(reason)}

          The default is HAKONIWA_TIME_SPEC_LEAN_RUNTIME=local, which uses a host Lean/Lake installation.
          Set HAKONIWA_TIME_SPEC_LEAN_RUNTIME=docker to use Docker,
          or HAKONIWA_TIME_SPEC_LEAN_RUNTIME=auto to prefer local Lake and fall back to Docker.
          """)
      end
    after
      File.rm_rf!(work_lean_dir)
    end
  end

  defp fresh_lean_workdir do
    Path.join([
      System.tmp_dir!(),
      "hakoniwa_time_spec_lean_#{System.unique_integer([:positive, :monotonic])}"
    ])
  end

  defp lean_runtime(lean_dir) do
    runtime =
      (System.get_env("HAKONIWA_TIME_SPEC_LEAN_RUNTIME") || "local")
      |> String.downcase()

    case runtime do
      "auto" ->
        if System.find_executable("lake") do
          local_runtime(lean_dir)
        else
          docker_runtime(lean_dir)
        end

      "local" ->
        local_runtime(lean_dir)

      "docker" ->
        docker_runtime(lean_dir)

      other ->
        flunk("""
        Unsupported HAKONIWA_TIME_SPEC_LEAN_RUNTIME value: #{inspect(other)}

        Supported values are: local, docker, auto.
        """)
    end
  end

  defp local_runtime(lean_dir) do
    {
      LeanLsp.Runtime.Local,
      [runtime: LeanLsp.Runtime.Local, workdir: lean_dir, timeout: @build_timeout],
      [workdir: lean_dir, timeout: @build_timeout]
    }
  end

  defp docker_runtime(lean_dir) do
    docker_image =
      System.get_env("HAKONIWA_TIME_SPEC_LEAN_DOCKER_IMAGE") ||
        "leanprovercommunity/lean4:latest"

    {
      LeanLsp.Runtime.Docker,
      [
        docker_image: docker_image,
        container_workspace_root: @container_workspace_root,
        mounts: [{lean_dir, @container_workspace_root, "rw"}]
      ],
      [workdir: @container_workspace_root, timeout: @build_timeout]
    }
  end

  defp assert_lake_build(runtime_module, runtime, exec_options) do
    command = ["lake", "build", "HakoniwaTimeSpec"]

    case runtime_module.exec(runtime, command, exec_options) do
      {:ok, %{exit_status: 0}} ->
        :ok

      {:ok, result} ->
        flunk("""
        Lean build returned an unexpected successful result.

        Command: #{Enum.join(command, " ")}
        Result: #{inspect(result)}
        """)

      {:error, {:command_failed, failure}} ->
        flunk("""
        Lean build failed.

        Command: #{Enum.join(command, " ")}
        Exit status: #{failure[:exit_status]}

        stdout:
        #{failure[:stdout]}

        stderr:
        #{failure[:stderr]}
        """)

      {:error, reason} ->
        flunk("""
        Lean build could not be executed through LeanLsp.

        Command: #{Enum.join(command, " ")}
        Reason: #{inspect(reason)}
        """)
    end
  end
end
