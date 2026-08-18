require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "sprockets/railtie" if defined?(Sprockets)

Bundler.require(*Rails.groups)

module CorreioContentHub
  class Application < Rails::Application
    config.load_defaults 8.0
    config.time_zone = "America/Sao_Paulo"
    config.active_record.default_timezone = :utc
    config.autoload_lib(ignore: %w[assets tasks])
  end
end
