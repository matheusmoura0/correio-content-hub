class AddEditorialSuggestionDecisions < ActiveRecord::Migration[8.0]
  def up
    add_column :editorial_edition_items, :decision, :string, null: false, default: "pending"
    add_reference :editorial_edition_items, :decided_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :editorial_edition_items, :decided_at, :datetime
    add_index :editorial_edition_items, [:article_id, :decision]
    add_column :sites, :editorial_checked_at, :datetime
    add_column :sites, :editorial_cycle_error, :string

    execute <<~SQL
      UPDATE editorial_edition_items AS items
      SET decision = CASE WHEN items.approved THEN 'approved'
        WHEN editions.status = 'ready' THEN 'pending' ELSE 'skipped' END,
        decided_by_id = CASE WHEN items.approved THEN editions.approved_by_id END,
        decided_at = CASE WHEN items.approved THEN editions.approved_at END
      FROM editorial_editions AS editions WHERE editions.id = items.editorial_edition_id
    SQL
  end

  def down
    remove_column :sites, :editorial_cycle_error
    remove_column :sites, :editorial_checked_at
    remove_index :editorial_edition_items, [:article_id, :decision]
    remove_column :editorial_edition_items, :decided_at
    remove_reference :editorial_edition_items, :decided_by, foreign_key: { to_table: :users }
    remove_column :editorial_edition_items, :decision
  end
end
