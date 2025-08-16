defmodule Mix.Tasks.Bench do
  @moduledoc """
  Run performance benchmarks for RulesEngine.

  Usage:
    mix bench                 # Run all benchmarks
    mix bench compilation     # Run compilation benchmarks only
    mix bench engine         # Run engine runtime benchmarks only
    mix bench --compare      # Compare with previous results
    mix bench --profile      # Run with memory profiling
  """

  use Mix.Task

  @shortdoc "Run RulesEngine performance benchmarks"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, targets, _} =
      OptionParser.parse(args,
        switches: [compare: :boolean, profile: :boolean, help: :boolean],
        aliases: [h: :help]
      )

    if opts[:help] do
      Mix.shell().info(@moduledoc)
      :ok
    else
      if opts[:profile] do
        Mix.shell().info("Starting memory profiling with :recon...")
        start_memory_monitoring()
      end

      case targets do
        [] ->
          run_all_benchmarks(opts)

        ["compilation"] ->
          run_compilation_benchmarks(opts)

        ["engine"] ->
          run_engine_benchmarks(opts)

        _ ->
          Mix.shell().error("Unknown benchmark target. Available: compilation, engine")
          System.halt(1)
      end

      if opts[:profile] do
        stop_memory_monitoring()
      end
    end
  end

  defp run_all_benchmarks(opts) do
    Mix.shell().info("Running all RulesEngine benchmarks...")
    run_compilation_benchmarks(opts)
    Mix.shell().info("")
    run_engine_benchmarks(opts)

    if opts[:compare] do
      compare_results()
    end
  end

  defp run_compilation_benchmarks(_opts) do
    Mix.shell().info("Running compilation benchmarks...")
    Code.require_file("bench/compilation_bench.exs")
  end

  defp run_engine_benchmarks(_opts) do
    Mix.shell().info("Running engine runtime benchmarks...")
    Code.require_file("bench/engine_bench.exs")
  end

  defp compare_results do
    Mix.shell().info("Comparing with previous benchmark results...")

    # Check if we have previous results to compare
    results_dir = "bench/results"
    check_results_directory(results_dir)
  end

  defp check_results_directory(results_dir) do
    if File.dir?(results_dir) do
      json_files = Path.wildcard("#{results_dir}/*.json")
      display_results(json_files)
    else
      Mix.shell().info("No benchmark results directory found.")
    end
  end

  defp display_results(json_files) do
    if Enum.empty?(json_files) do
      Mix.shell().info("No previous benchmark results found for comparison.")
    else
      Mix.shell().info("Previous benchmark results:")

      Enum.each(json_files, fn file ->
        Mix.shell().info("  - #{Path.basename(file)}")
      end)
    end
  end

  defp start_memory_monitoring do
    spawn(fn -> memory_monitor_loop() end)
  end

  defp memory_monitor_loop do
    Process.sleep(1000)

    memory_info = :erlang.memory()
    process_count = length(Process.list())

    IO.puts("Memory: #{inspect(memory_info)}")
    IO.puts("Process count: #{process_count}")

    memory_monitor_loop()
  end

  defp stop_memory_monitoring do
    Mix.shell().info("Memory profiling complete.")
  end
end
