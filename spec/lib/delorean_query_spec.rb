require "spec_helper"

module Marty

bud_cats =<<EOF
name
Conv Fixed 30
Conv Fixed 20
EOF

fannie_bup =<<EOF
bud_category	note_rate	buy_up	buy_down	settlement_mm	settlement_yy
Conv Fixed 30	2.250	4.42000	7.24000	12	2012
Conv Fixed 30	2.375	4.42000	7.24000	12	2012
Conv Fixed 30	2.500	4.41300	7.22800	12	2012
Conv Fixed 30	2.625	4.37500	7.16200	12	2012
Conv Fixed 30	2.750	4.32900	7.09300	12	2012
Conv Fixed 20	2.875	4.24800	6.95900	12	2012
Conv Fixed 20	2.875	4.24800	6.95900	11	2012
EOF

script =<<EOF
A:
    c = Gemini::FannieBup.
      joins("bud_category").
      where("name LIKE '%30'").
      count

    s = Gemini::FannieBup.
      joins("bud_category").
      select("name").
      distinct("name").
      pluck("name")

    o = Gemini::FannieBup.
      order("note_rate DESC", "buy_down ASC").
      select("note_rate").
      first.note_rate

    g = Gemini::FannieBup.
      select("settlement_yy*settlement_mm AS x, count(*) AS c").
      group("settlement_mm", "settlement_yy").
      order("settlement_mm").to_a

    gg = [r.attributes for r in g]

    n = Gemini::FannieBup.where.not("settlement_mm < 12").count
EOF

  describe 'DeloreanQuery' do
    before(:each) do
      marty_whodunnit
      Marty::DataImporter.do_import_summary(Gemini::BudCategory, bud_cats)
      Marty::DataImporter.do_import_summary(Gemini::FannieBup, fannie_bup)

      Marty::Script.load_script_bodies(
        {
          "A" => script,
        }, Date.today)

      @engine = Marty::ScriptSet.new.get_engine("A")
    end

    it "perfroms join+count" do
      res = @engine.evaluate("A", "c", {})

      expect(res).to eq Gemini::FannieBup.
                          joins("bud_category").
                          where("name LIKE '%30'").
                          count

    end

    it "perfroms select+distinct" do
      res = @engine.evaluate("A", "s", {})

      expect(res).to eq Gemini::FannieBup.
                          joins("bud_category").
                          select("name").
                          distinct("name").
                          pluck("name")
    end

    it "perfroms order+first" do
      res = @engine.evaluate("A", "o", {})

      expect(res).to eq Gemini::FannieBup.
                          order("note_rate DESC", "buy_down ASC").
                          select("note_rate").
                          first.note_rate
    end

    it "perfroms group+count" do
      res = @engine.evaluate("A", "gg", {})

      expect(res).
        to eq Gemini::FannieBup.
                select("settlement_yy*settlement_mm AS x, count(*) AS c").
                group("settlement_mm", "settlement_yy").
                order("settlement_mm").
                map(&:attributes)
    end

    it "perfroms where+not" do
      res = @engine.evaluate("A", "n", {})

      expect(res).to eq Gemini::FannieBup.where.not("settlement_mm < 12").count
    end
  end
end
