class AddPeriodEndToAnalyticsEmailDeliveries < ActiveRecord::Migration[8.1]
  def change
    add_column :analytics_email_deliveries, :period_end, :date
  end
end
