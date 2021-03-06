require 'spec_helper'

feature 'logger view', js: true, capybara: true do

  def manual_insert(type, message, ts, detail)
    stmt = @db.prepare <<-SQL
       INSERT INTO log (message_type, message, timestamp, details)
       VALUES (?, ?, ?, ?)
    SQL
    stmt.bind_param(1, type)
    stmt.bind_param(2, message)
    stmt.bind_param(3, ts)
    stmt.bind_param(4, detail)
    stmt.execute
    stmt.close
  end

  before(:all) do
    self.use_transactional_fixtures = false
    @db =  SQLite3::Database.new(Marty::Log.logfile)

    info_s = { info: 'message' }
    error_s = [1, 2, 3, { error: 'message' }]
    fatal_s = ["string", 123, { fatal: "message", another_key: 'value' }]
    Marty::Logger.info('info message', nil)
    Marty::Logger.error('error message', error_s)
    Marty::Logger.fatal('fatal message', fatal_s)
    manual_insert("debug", "hi mom", (Time.zone.now - 5.days).to_i,
                  ["one", "two", 3, 4.0].pretty_inspect)
    manual_insert("warn", "all your base", (Time.zone.now - 10.days).to_i,
                  [5].pretty_inspect)
    @ts = (@db.execute "select timestamp from log order by timestamp desc").map do
      |(ts)|
      Time.zone.at(ts).strftime('%Y-%m-%dT%H:%M:%S.%L%:z')
    end

    @clean_file = "/tmp/clean_#{Process.pid}.psql"
    save_clean_db(@clean_file)
    populate_test_users
  end

  after(:all) do
    restore_clean_db(@clean_file)
    @db.execute "delete from log"
    @db.close
    self.use_transactional_fixtures = true
  end

  let(:logview) { netzke_find('log_view') }
  it "updates views correctly" do
    log_in_as('marty')
    press('System')
    show_submenu('Log Maintenance')
    press('View Log')
    wait_for_ready
    exp_types = ["fatal", "error", "info", "debug", "warn"]
    exp_messages = ["fatal message", "error message",
                    "info message", "hi mom", "all your base"]
    exp_details = [ "[\"string\", 123, {:fatal=>\"message\", "\
                     ":another_key=>\"value\"}]\n",
                    "[1, 2, 3, {:error=>\"message\"}]\n",
                    "nil\n",
                    "[\"one\", \"two\", 3, 4.0]\n",
                    "[5]\n"]
    [[nil, 5], [7, 4], [3, 3], [0, 0]].each do |days, exp_count|
      if days
        press('System')
        show_submenu('Log Maintenance')
        press('Cleanup Log Table')
        wait_for_ajax
        find(:xpath, "//input[contains(@id, 'textfield')]", wait: 5).set(days)
        press('OK')
        wait_for_ready
        find(:refresh).click
        wait_for_ready
      end
      cnt = logview.row_count()
      expect(cnt).to eq(exp_count)
      types = logview.col_values('message_type', cnt, 0)
      messages = logview.col_values('message', cnt, 0)
      details = logview.col_values('details', cnt, 0).
                map { |d| CGI.unescapeHTML(d) }
      ts = logview.col_values('timestamp', cnt, 0)
      expect(ts).to eq(@ts.slice(0,exp_count))
      expect(types).to eq(exp_types.slice(0,exp_count))
      expect(messages).to eq(exp_messages.slice(0,exp_count))
      expect(details).to eq(exp_details.slice(0,exp_count))
    end
  end
end
