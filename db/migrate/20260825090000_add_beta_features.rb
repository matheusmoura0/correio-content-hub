class AddBetaFeatures < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :name, :string
    add_column :users, :role, :string, null: false, default: "member"
    add_index :users, :role

    create_table :topics do |t|
      t.string :name, null: false
      t.text :keywords, null: false
      t.string :match_mode, null: false, default: "any"
      t.boolean :active, null: false, default: true
      t.datetime :last_run_at
      t.timestamps
    end

    create_table :topic_articles do |t|
      t.references :topic, null: false, foreign_key: true
      t.references :article, null: false, foreign_key: true
      t.text :matched_terms
      t.timestamps
    end
    add_index :topic_articles, [:topic_id, :article_id], unique: true

    add_column :articles, :rewritten_title, :string
    add_column :articles, :rewritten_content, :text
    add_column :articles, :rewrite_instructions, :text
    add_column :articles, :rewritten_at, :datetime
    add_reference :articles, :rewritten_by, foreign_key: { to_table: :users }
  end
end
