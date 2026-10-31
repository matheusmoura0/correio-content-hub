class AddEditorialKeywordsToSites < ActiveRecord::Migration[8.0]
  class MigrationSite < ActiveRecord::Base
    self.table_name = "sites"
  end

  def up
    add_column :sites, :editorial_keywords, :text, default: "", null: false
    MigrationSite.reset_column_information
    MigrationSite.find_each do |site|
      site.update_columns(editorial_keywords: Publishing::EditorialPolicy.default_terms(site))
    end
  end

  def down
    remove_column :sites, :editorial_keywords
  end
end
