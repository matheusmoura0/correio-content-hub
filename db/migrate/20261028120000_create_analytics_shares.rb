class CreateAnalyticsShares < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_shares do |t|
      t.references :site, null: false, foreign_key: true, index: { unique: true }
      t.string :token, null: false
      t.timestamps
    end
    add_index :analytics_shares, :token, unique: true
  end
end
