class PromoteExistingAdmin < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE users
      SET role = 'admin'
      WHERE id = (SELECT MIN(id) FROM users)
    SQL
  end

  def down
    # A reversão não remove privilégios para evitar bloquear a única conta administrativa.
  end
end
