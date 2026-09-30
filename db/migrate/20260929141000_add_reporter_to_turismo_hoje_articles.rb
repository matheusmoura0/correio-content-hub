class AddReporterToTurismoHojeArticles < ActiveRecord::Migration[8.0]
  def change
    add_reference :articles, :reported_by, foreign_key: { to_table: :users }, index: true
  end
end
