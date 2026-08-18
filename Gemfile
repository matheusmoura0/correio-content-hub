source "https://rubygems.org"

ruby ">= 3.2.0"

gem "rails", "~> 8.0"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "propshaft"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "devise"
gem "feedjira"

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
