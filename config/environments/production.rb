require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?
  ssl_enabled = ENV.fetch("FORCE_SSL", "true") != "false"
  config.force_ssl = ssl_enabled
  config.assume_ssl = ssl_enabled
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger($stdout)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.active_support.report_deprecations = false
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [:id]
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "localhost") }
  config.action_mailer.perform_caching = false
  config.i18n.fallbacks = true
end
