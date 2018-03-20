module Marty::Diagnostic; class Base < Request
  extend Packer
  include ActionView::Helpers::TextHelper

  # all diagnostics have `aggregatable` set to true.
  # aggregatable indicates to the reporting mechanism that a diagnostic
  # should be aggregated  as these types of diagnostics are
  # aggregated differently (or not at all).
  class_attribute :aggregatable, :status_only

  @@read_only = Marty::Util.db_in_recovery?
  @@template  = ActionController::Base.new.lookup_context.
                  find_template("marty/diagnostic/diag").identifier

  def self.diagnostic_fn opts={}
    opts.each do |k,v|
      send("#{k}=", v)
    end
    class << self
      define_method :generate do
        pack{yield}
      end
    end
  end

  diagnostic_fn aggregatable: true, status_only: false do
    raise "generate has not been defined for #{name}"
  end

  def self.fatal?
    name.include?('Fatal')
  end

  def self.process_status_only infos
    return infos unless status_only
    infos.map{|info| info.map{|test, result| [test, result['status']]}.to_h}
  end

  def self.get_difference data
    values = process_status_only(data.values)
    Marty::DataExporter.hash_array_merge(values, true).map{
      |test, values|
      test if values.uniq.count > 1
    }.compact
  end

  def self.apply_consistency data
    diff = get_difference(data)
    data.each_with_object({}){
      |(node, diagnostic), new_data|
      new_data[node] = diagnostic.each_with_object({}){
        |(test, info), new_diagnostic|
        new_diagnostic[test] = info + {'consistent' => !diff.include?(test)}
      }
    }
  end

  def self.consistent? data
    process_status_only(data.values).uniq.count == 1
  end

  def self.display data
    consistent = consistent?(data)
    success    = consistent && !fatal?
    ERB.new(File.open(@@template).read).result(binding)
  end

  def self.display_info_css info
    return 'inconsistent' if info.nil? || (info['status'] &&
                                           info['consistent'] == false)
    return 'error' unless info['status']
    'passed'
  end

  def self.display_info_description info
    new.simple_format(info ? info['description'] : 'N/A')
  end
end
end
