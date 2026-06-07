defmodule SymphonyElixir.MixProject do
  use Mix.Project

  def project,
    do: [
      app: :symphony_elixir,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [check: ["format", "test"]],
      releases: releases()
    ]

  def application,
    do: [
      extra_applications: [:logger, :crypto, :inets, :ssl],
      mod: {SymphonyElixir.Application, []}
    ]

  defp releases do
    [
      symphony_elixir: [
        include_erts: true,
        include_executables_for: [:unix, :windows],
        applications: [symphony_elixir: :permanent],
        strip_beams: Mix.env() == :prod
      ]
    ]
  end

  defp deps,
    do: [
      {:jason, "~> 1.4"},
      {:plug, "~> 1.18"},
      {:bandit, "~> 1.8"},
      {:yaml_elixir, "~> 2.11"},
      {:req, "~> 0.5"}
    ]
end
