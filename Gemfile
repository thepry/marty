source "http://rubygems.org"

# Declare your gem's dependencies in marty.gemspec.
# Bundler will treat runtime dependencies like base dependencies, and
# development dependencies will be added by default to the :development group.
gemspec

gem 'delayed_job_active_record'
gem 'daemons', '~> 1.1.9'
gem 'mime-types', '< 3.0', platforms: :ruby_19
gem 'rails', '~> 5.1.1'
gem 'pg', '~> 0.18.4'
gem 'sqlite3'

group :development, :test do
  gem 'pry-rails'
  gem 'rspec-rails'
  gem 'capybara'
  gem 'selenium-webdriver'
  gem 'chromedriver-helper'
  gem 'timecop'
  gem 'database_cleaner'
  gem 'rails-controller-testing'

  gem 'netzke-core'
  gem 'netzke-basepack'
  gem 'netzke-testing'

  gem 'marty_rspec'

end
