module Marty; class DataGridView < McflyGridPanel
  has_marty_permissions create: [:admin, :dev],
                        read: :any,
                        update: [:admin, :dev],
                        delete: [:admin, :dev]

  include Extras::Layout

  def self.show_grid_js(options={})
    dg        = options[:data_grid] || 'data_grid'
    title_str = options[:title_str] || 'Data Grid'

    javascript = l(<<-JS)
    function() {
       var sel = this.getSelectionModel().selected.first();
       var record_id = sel && sel.getId();
       this.server.showGrid({record_id: record_id,
                            data_grid: "#{dg}",
                            title_str: "#{title_str}"});
    }
    JS
    javascript
  end

  def self.client_show_grid_js
    javascript = l(<<-JS)
    function(count, data, title_str) {
       var columns = [];
       var fields  = [];

       for (var i=0; i<count; i++) {
          fields.push("a" + i);
          columns.push({dataIndex: "a" + i, text: i, flex: 1});
       }

       Ext.create('Ext.Window', {
         height:        "80%",
         width:         "80%",
         x:             0,
         y:             0,
         autoWidth:     true,
         modal:         true,
         autoScroll:    true,
         title:         title_str,
         items: {
           xtype:       'grid',
           border:      false,
           hideHeaders: false,
           columns:     columns,
           store:       Ext.create('Ext.data.ArrayStore', {
             fields: fields,
             data: data,
             })
         },
      }).show();
    }
    JS
    javascript
  end

  client_class do |c|
    c.netzke_show_grid        = DataGridView.show_grid_js
    c.netzke_client_show_grid = DataGridView.client_show_grid_js
  end

  def configure(c)
    super

    c.title   = I18n.t('data_grid')
    c.model   = "Marty::DataGrid"
    c.attributes =
      [
       :name,
       :vcols,
       :hcols,
       :lenient,
       :data_type,
       :created_dt,
      ]

    c.store_config.merge!({sorters:  [{property: :name, direction: 'ASC'}]})
    c.editing      = :in_form
    c.paging       = :pagination
    c.multi_select = false
  end

  endpoint :add_window__add_form__submit do |params|
    data = ActiveSupport::JSON.decode(params[:data])

    return client.netzke_notify("Permission Denied") if
      !config[:permissions][:create]

    begin
      DataGrid.create_from_import(data["name"], data["export"])
      client.success = true
      client.netzke_on_submit_success
    rescue => exc
      client.netzke_notify(exc.to_s)
    end
  end

  endpoint :edit_window__edit_form__submit do |params|
    data = ActiveSupport::JSON.decode(params[:data])

    dg = DataGrid.find_by_id(data["id"])

    begin
      dg.update_from_import(data["name"], data["export"])
      client.success = true
      client.netzke_on_submit_success
    rescue => exc
      client.netzke_notify(exc.to_s)
    end
  end

  action :show_grid do |a|
    a.text    = "Show Grid"
    a.icon    = :application_view_detail
    a.handler = :netzke_show_grid
  end

  endpoint :show_grid do |params|
    record_id = params[:record_id]

    dg = DataGrid.find_by_id(record_id)

    return client.netzke_notify("No data grid.") unless dg

    meta_rows_raw, h_key_rows, data_rows = dg.export_array
    meta_rows = meta_rows_raw.map do |row|
      # need to escape for HTML, otherwise characters such as >, <,
      # etc. not displayed properly.
      row.map { |field| CGI::escapeHTML(field) }
    end
    res = meta_rows + [[]] + h_key_rows + data_rows

    maxcount = res.map(&:length).max

    client.netzke_client_show_grid maxcount, res, 'Data Grid'
  end

  def default_bbar
    [:show_grid] + super
  end

  def default_context_menu
    []
  end

  def default_form_items
    [
     :name,
     textarea_field(:export, height: 300, hide_label: true),
    ]
  end

  component :edit_window do |c|
    super(c)
    c.width = 700
  end

  component :add_window do |c|
    super(c)
    c.width = 700
  end

  attribute :name do |c|
    c.width = 120
  end

  attribute :hcols do |c|
    c.label  = "Horizontal Attrs"
    c.width  = 200
    c.getter = lambda { |r|
      r.dir_infos("h").map {|inf| inf["attr"]}.join(', ')
    }
  end

  attribute :vcols do |c|
    c.label  = "Vertical Attrs"
    c.width  = 200
    c.getter = lambda { |r|
      r.dir_infos("v").map {|inf| inf["attr"]}.join(', ')
    }
  end

  attribute :lenient do |c|
    c.width  = 75
  end

  attribute :data_type do |c|
    c.label  = "Data Type"
    c.width  = 200
  end

  attribute :created_dt do |c|
    c.label     = I18n.t('updated_at')
    c.format    = "Y-m-d H:i"
    c.read_only = true
  end
end; end

DataGridView = Marty::DataGridView
