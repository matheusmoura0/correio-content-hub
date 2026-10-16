class AddHubContentCapabilityToSites < ActiveRecord::Migration[8.0]
  def up
    add_column :sites, :receives_hub_content, :boolean, null: false, default: true

    execute <<~SQL.squish
      UPDATE sites
      SET receives_hub_content = FALSE
      WHERE lower(regexp_replace(domain, '^www\\.', '')) = 'correiodamanha.com.br'
         OR publication_key = 'correio-da-manha'
         OR lower(name) = 'correio da manhã'
    SQL
  end

  def down
    remove_column :sites, :receives_hub_content
  end
end
