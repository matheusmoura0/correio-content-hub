class AddBarraLayoutProfile < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE sites
      SET layout_profile = 'barra', updated_at = CURRENT_TIMESTAMP
      WHERE publication_key = 'jornal-da-barra'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE sites
      SET layout_profile = 'standard', updated_at = CURRENT_TIMESTAMP
      WHERE publication_key = 'jornal-da-barra'
    SQL
  end
end
