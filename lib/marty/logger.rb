require 'sqlite3'

class Marty::Logger

  def self.method_missing(m, *args, &block)
    return super unless
      [:debug, :info, :warn, :error, :fatal, :unknown].include?(m)
    Marty::Util.logger.send(m, args[0]) if Marty::Util.logger.respond_to?(m)
    log(m, *args)
  end

  def self.log(type, message, details=nil)
    Marty::Log.write_log(type, message, details)
  end

  def self.with_logging(error_message, error_data)
    begin
      yield
    rescue => e
      error(error_message, { message: e.message,
                             data: error_data })
      raise "#{error_message}: #{e.message}"
    end
  end

end
