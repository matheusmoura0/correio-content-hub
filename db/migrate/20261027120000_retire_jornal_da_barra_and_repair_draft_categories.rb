class RetireJornalDaBarraAndRepairDraftCategories < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE sites SET active = FALSE, receives_hub_content = FALSE,
        content_mode = 'external', updated_at = CURRENT_TIMESTAMP
      WHERE lower(btrim(domain)) ~ '^(www[.])?jornaldabarra[.]'
        OR lower(btrim(publication_key)) = 'jornal-da-barra'
        OR lower(btrim(name)) = 'jornal da barra'
    SQL

    # Expire affected proposals, without rewriting any completed editorial decision.
    execute <<~SQL
      UPDATE editorial_editions AS editions SET status = 'expired', updated_at = CURRENT_TIMESTAMP
      FROM sites WHERE editions.site_id = sites.id AND editions.status = 'ready'
        AND (lower(btrim(sites.domain)) ~ '^(www[.])?jornaldabarra[.]'
          OR lower(btrim(sites.publication_key)) = 'jornal-da-barra'
          OR lower(btrim(sites.name)) = 'jornal da barra'
          OR EXISTS (SELECT 1 FROM editorial_edition_items i JOIN categories c ON c.id = i.category_id
            WHERE i.editorial_edition_id = editions.id AND i.decision = 'pending' AND c.site_id <> editions.site_id))
    SQL
    execute <<~SQL
      UPDATE editorial_edition_items AS items SET decision = 'skipped', updated_at = CURRENT_TIMESTAMP
      FROM editorial_editions AS editions
      WHERE items.editorial_edition_id = editions.id AND editions.status = 'expired' AND items.decision = 'pending'
    SQL

    # Unknown draft categories need a new choice; do not change live publications.
    execute <<~SQL
      UPDATE site_articles AS distributions SET category_id = NULL, updated_at = CURRENT_TIMESTAMP
      FROM categories WHERE distributions.category_id = categories.id
        AND distributions.site_id <> categories.site_id AND distributions.status = 'draft'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Restoring retired destinations or invalid categories requires an explicit review."
  end
end
