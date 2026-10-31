source "https://rubygems.org"

ruby "3.3.12"

gem "rails", "~> 8.1.3"
gem "json", "< 3"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "propshaft"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "devise"
gem "devise-i18n"
gem "rails-i18n"
gem "feedjira"
gem "prawn", "~> 2.5"
gem "ruby-vips", "~> 2.3"
gem "browser", "~> 6.0"
gem "maxmind-db", "~> 1.3", require: "maxmind/db"

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
end

group :development do
  gem "web-console"
end

group :test do
  gem "minitest", "~> 5.25"
  gem "capybara"
  gem "selenium-webdriver"
end
