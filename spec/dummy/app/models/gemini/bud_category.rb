module Gemini
  class BudCategory < ActiveRecord::Base
    self.table_name = 'gemini_bud_categories'
    has_mcfly append_only: true
    mcfly_validates_uniqueness_of :name
  end
end
