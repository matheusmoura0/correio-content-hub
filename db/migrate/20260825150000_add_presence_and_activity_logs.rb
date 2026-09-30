class AddPresenceAndActivityLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :last_seen_at, :datetime
    add_index :users, :last_seen_at

    create_table :activity_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :event, null: false
      t.string :description, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.timestamps
    end

    add_index :activity_logs, :created_at
    add_index :activity_logs, [:subject_type, :subject_id]
  end
end
