import Config

# Вътрешен HTTP микросървиз зад Next прокси — без force_ssl (TLS е на ръба).

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
