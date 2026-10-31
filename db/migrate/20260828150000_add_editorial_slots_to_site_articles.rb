class AddEditorialSlotsToSiteArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :site_articles, :slot_key, :string
    add_column :site_articles, :assignment_mode, :string, null: false, default: "automatic"
    add_index :site_articles, [:site_id, :slot_key]
    add_index :site_articles, [:site_id, :assignment_mode]

    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE site_articles
          SET slot_key = placement
          WHERE placement IN ('hero', 'editor_pick')
        SQL
      end
    end
  end
end
