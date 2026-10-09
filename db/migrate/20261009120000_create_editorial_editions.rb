class CreateEditorialEditions < ActiveRecord::Migration[8.0]
  def change
    create_table :editorial_editions do |t|
      t.references :site, null: false, foreign_key: true
      t.string :status, null: false, default: "ready"
      t.string :page_digest, null: false
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :approved_at
      t.timestamps
    end
    add_index :editorial_editions, :site_id, unique: true, where: "status = 'ready'", name: "one_ready_edition_per_site"
    create_table :editorial_edition_items do |t|
      t.references :editorial_edition, null: false, foreign_key: true
      t.references :article, null: false, foreign_key: { on_delete: :cascade }
      t.references :category, foreign_key: { on_delete: :nullify }
      t.string :slot_key, null: false
      t.string :article_digest, null: false
      t.string :title, null: false
      t.boolean :approved, null: false, default: false
      t.timestamps
    end
    add_index :editorial_edition_items, [:editorial_edition_id, :slot_key], unique: true
  end
end
