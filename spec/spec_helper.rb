ENV["RAILS_ENV"] ||= "test"

require 'dummy/config/application'
require 'rspec/rails'
require 'database_cleaner'
require 'marty_rspec'

Dummy::Application.initialize! unless Dummy::Application.initialized?

ActiveRecord::Migrator.migrate File.expand_path("../../db/migrate/", __FILE__)
ActiveRecord::Migrator.migrate File.expand_path("../dummy/db/migrate/", __FILE__)

Dir[Rails.root.join("../support/**/*.rb")].each { |f| require f }

def register_chrome_driver driver = :chrome, options={}
  Capybara.register_driver driver do |app|
    caps = Selenium::WebDriver::Remote::Capabilities.
             chrome(options + {pageLoadStrategy: 'none'})

    Capybara::Selenium::Driver.new(app,
                                   browser: :chrome,
                                   desired_capabilities: caps)
  end
end

CLASSES_TO_EXCLUDE_FROM_SHARED = ["Marty::Log"]
class ActiveRecord::Base
  mattr_accessor :shared_connection
  class << self
    alias_method :orig_connection, :connection
  end
  def self.clear_connection
    @@shared_connection = nil
  end

  clear_connection

  def self.connection
    CLASSES_TO_EXCLUDE_FROM_SHARED.include?(model_name) ? orig_connection :
      @@shared_connection ||
      ConnectionPool::Wrapper.new(:size => 1) {retrieve_connection}
  end

  def self.reset_shared_connection
    @@shared_connection = ConnectionPool::Wrapper.
                            new(:size => 1) {retrieve_connection}
  end
end

register_chrome_driver
register_chrome_driver(:headless,
                       chromeOptions: {
                         args: %w[headless disable-gpu window-size=3840,2160]
                       })

Capybara.javascript_driver = ENV['HEADLESS'] == 'true' ? :headless : :chrome

ActiveRecord::Base.shared_connection = ActiveRecord::Base.connection

RSpec.configure do |config|
  config.include DelayedJobHelpers
  config.include CleanDbHelpers
  config.include SpecSetup
  config.include Marty::IntegrationHelpers
  config.include MartyRSpec::Util

  Capybara.default_max_wait_time = 3

  # TODO: Continue to remove should syntax from specs - remove this line to see
  # errors
  config.expect_with(:rspec) { |c| c.syntax = [:should, :expect] }

  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  config.order = 'random'

  config.example_status_persistence_file_path = '.rspec-results'

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
    Rails.application.load_seed
  end

  config.before(:each) do
    Mcfly.whodunnit = UserHelpers.system_user
  end

  config.after(:each, :js => true) do |example|
    # save a screenshot on js failures for CI server testing
    if example.exception
      meta = example.metadata
      filename = File.basename(meta[:file_path])
      line_number = meta[:line_number]
      screenshot_name = "screenshot-#{filename}-#{line_number}.png"
      screenshot_path = "#{Rails.root.join("tmp")}/#{screenshot_name}"
      page.save_screenshot(screenshot_path)
     end
  end

  config.infer_spec_type_from_file_location!
  config.use_transactional_fixtures = true

  Netzke::Testing.rspec_init(config)

  # FIXME: temporary monkey patch to fix marty_rspec for new extjs/rails
  module MartyRSpec
    module Components
      class NetzkeGrid
        def get_row_vals row
          res = run_js <<-JS
          #{ext_var(grid, 'grid')}
          return Ext.encode(#{ext_row(row.to_i - 1, 'grid')}.data);
          JS
          JSON.parse(res)
        end
      end
    end
  end
end
