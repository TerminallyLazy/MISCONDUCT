import Config

if config_env() == :test do
  config :symphony_elixir, http_enabled: false
else
  config :symphony_elixir, http_enabled: true
end
