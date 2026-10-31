class RetireCorreioEconomicoFromHub < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE sites
      SET active = FALSE, receives_hub_content = FALSE, content_mode = 'external', updated_at = CURRENT_TIMESTAMP
      WHERE lower(btrim(domain)) ~ '^(www[.])?correioeconomico[.]'
         OR lower(btrim(publication_key)) = 'correio-economico'
         OR lower(btrim(name)) IN ('correio econômico', 'correio economico')
    SQL

    execute <<~SQL
      UPDATE editorial_edition_items AS items
      SET decision = 'skipped', updated_at = CURRENT_TIMESTAMP
      FROM editorial_editions AS editions, sites
      WHERE items.editorial_edition_id = editions.id AND editions.site_id = sites.id
        AND editions.status = 'ready' AND items.decision = 'pending'
        AND (lower(btrim(sites.domain)) ~ '^(www[.])?correioeconomico[.]'
          OR lower(btrim(sites.publication_key)) = 'correio-economico'
          OR lower(btrim(sites.name)) IN ('correio econômico', 'correio economico'))
    SQL

    execute <<~SQL
      UPDATE editorial_editions AS editions
      SET status = 'expired', updated_at = CURRENT_TIMESTAMP
      FROM sites
      WHERE editions.site_id = sites.id AND editions.status = 'ready'
        AND (lower(btrim(sites.domain)) ~ '^(www[.])?correioeconomico[.]'
          OR lower(btrim(sites.publication_key)) = 'correio-economico'
          OR lower(btrim(sites.name)) IN ('correio econômico', 'correio economico'))
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "CMS ownership must not be reverted automatically."
  end
end
