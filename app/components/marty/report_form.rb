require 'delorean_lang'

class Marty::ReportForm < Marty::CmFormPanel

  attr_accessor :filename

  # override apply for background generation
  action :apply do |a|
    a.text	= a.tooltip = I18n.t("reporting.background")
    a.handler	= :on_apply
    a.icon	= :report_disk
    a.disabled	= false
  end

  action :generate do |a|
    a.text	= a.tooltip = I18n.t("reporting.generate")
    a.handler	= :on_generate
    a.icon	= :report_go
    a.disabled	= false
  end

  ######################################################################

  def configure_bbar(c)
    c[:bbar] = [
                '->',
                :apply,
                :generate,
               ]
  end

  ######################################################################

  def _get_report_engine(params)
    d_params = ActiveSupport::JSON.decode(params[:data] || "{}")
    d_params.each_pair do |k,v|
      d_params[k] = nil if v.blank? || v == "null"
    end

    [Marty::ScriptSet.get_engine(session[:selected_script_id]), d_params]
  end

  def run_eval(params)
    engine, d_params = _get_report_engine(params)

    begin
      return engine.evaluate(session[:selected_node], "result", d_params)

    rescue => exc
      Marty::Util.logger.error "run_eval failed: #{exc.backtrace}"

      res = Delorean::Engine.grok_runtime_exception(exc)
      res["backtrace"] =
        res["backtrace"].map {|m, line, fn| "#{m}:#{line} #{fn}"}.join('\n')
      res
    end
  end

  def generate_csv(params={})
    res = run_eval(params)
    Marty::ContentHandler.export(res, "csv", "").first
  end

  # Used for testing
  def generate_txt(params={})
    generate_csv(params)
  end

  def generate_xlsx(params={})
    res = run_eval(params)
    Marty::ContentHandler.export(res, "xlsx", "").first
  end

  def generate_zip(params={})
    res = run_eval(params)
    Marty::ContentHandler.export(res, "zip", "result").first
  end

  endpoint :netzke_submit do |params, this|
    # We get here when user is asking for a background report

    engine, d_params = _get_report_engine(params)

    d_params["p_title"] ||= engine.
      evaluate(session[:selected_node], "title", {}).to_s

    # start background promise to get report result
    engine.background_eval(session[:selected_node],
                           d_params,
                           ["result", "title", "format"],
                           )

    this.netzke_feedback "Report can be accessed from the Jobs Dashboard ..."
  end

  ######################################################################

  js_configure do |c|
    c.on_generate = <<-JS
    function() {
      var values = this.getForm().getValues();
      var data = escape(Ext.encode(values));
      // FIXME: seems pretty hacky
      window.location = "#{Marty::Util.marty_path}/components/#{self.name}." + \
      	this.repformat + "?data=" + data;
    }
    JS
  end

  endpoint :netzke_load do |params, this|
  end

  def eval_form_items(items)
    case items
    when Array
      items.map {|x| eval_form_items(x)}
    when Hash
      items.each_with_object({}) { |(key, value), result|
        result[key] = eval_form_items(value)
      }
    when String
      items.starts_with?(':') ? items[1..-1].to_sym : items
    when Class
      raise "bad value in form #{items}" unless
        items < Delorean::BaseModule::BaseClass

      attrs = @engine.enumerate_attrs_by_node(items)

      @engine.evaluate_attrs_hash(items, attrs, {})
    else
      raise "bad value in form #{items}"
    end
  end

  def configure(c)
    super

    if session[:selected_script_id].nil? || session[:selected_node].nil?
      c.title = "No Report selected."
      return
    end

    begin
      @engine = Marty::ScriptSet.get_engine(session[:selected_script_id])
      raise @engine.to_s if @engine.is_a?(Hash)
      selected_ver = Marty::Script.
        find_by_id(session[:selected_script_id]).version
      script_name  = Marty::Script.
        find_by_id(session[:selected_script_id]).name
      latest_ver   = Marty::Script.
        where("name = ? and obsoleted_dt = 'infinity'",
              script_name)[0].version
      version = selected_ver.match(/^#{latest_ver}$/) ? nil : selected_ver

      items, title, format = @engine.
        evaluate_attrs(session[:selected_node], ["form", "title", "format"], {})

      raise "bad form items" unless items.is_a?(Array)
      raise "bad format" unless ["csv", "xlsx", "zip"].member?(format)

    rescue => exc
      c.title = "ERROR"
      c.items = [
                 {
                   field_label:	'Exception',
                   xtype: 	:displayfield,
                   name: 	'displayfield1',
                   value: 	"<span style=\"color:red;\">#{exc}</span>"
                 },
                ]
      return
    end

    items = Marty::Xl.symbolize_keys(eval_form_items(items), ':')

    items = [{html: "<br><b>No input is needed for this report.</b>"}] if
      items.empty?

    self.filename = version.nil? ? title.to_s : "#{title}_#{version}"

    c.items	= items
    c.repformat	= format
    c.title	= "Generate: #{title}"
    c.title	+= "-#{version}" if version
  end
end

ReportForm = Marty::ReportForm
