class CreateAnalyticsEmailReports < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_email_schedules do |t|
      t.references :site, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.jsonb :recipients, null: false, default: []
      t.integer :hour, null: false, default: 8
      t.timestamps
    end

    create_table :analytics_email_deliveries do |t|
      t.references :analytics_email_schedule, null: false, foreign_key: true, index: { name: "idx_analytics_delivery_schedule" }
      t.date :period_start, null: false
      t.string :recipient, null: false
      t.string :run_key, null: false, default: "weekly"
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.string :error_code
      t.datetime :attempted_at
      t.datetime :accepted_at
      t.timestamps
    end
    add_index :analytics_email_deliveries, [:analytics_email_schedule_id, :period_start, :recipient, :run_key], unique: true, name: "idx_analytics_delivery_unique"
    add_index :analytics_email_deliveries, [:status, :attempted_at], name: "idx_analytics_delivery_retry"
  end
end
