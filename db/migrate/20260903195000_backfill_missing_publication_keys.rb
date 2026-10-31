class BackfillMissingPublicationKeys < ActiveRecord::Migration[8.0]
  def up
    return unless column_exists?(:sites, :publication_key)

    execute <<~SQL
      UPDATE sites
      SET publication_key = 'legacy-site-' || id
      WHERE publication_key IS NULL OR btrim(publication_key) = ''
    SQL

    change_column_null :sites, :publication_key, false
  end

  def down
    # A chave de publicação identifica URLs públicas e não deve ser removida.
  end
end
