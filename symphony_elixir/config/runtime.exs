import Config

http_enabled =
  System.get_env("SYMPHONY_HTTP_ENABLED", "true")
  |> String.downcase()
  |> Kernel.in(["1", "true", "yes", "on"])

config :symphony_elixir,
  http_enabled: http_enabled,
  http_host: System.get_env("SYMPHONY_HTTP_HOST", "127.0.0.1"),
  http_port: System.get_env("SYMPHONY_HTTP_PORT") || System.get_env("PORT"),
  workflow_path: System.get_env("SYMPHONY_WORKFLOW_PATH")
