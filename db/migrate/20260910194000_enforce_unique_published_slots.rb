class EnforceUniquePublishedSlots < ActiveRecord::Migration[8.0]
  INDEX_NAME = "index_site_articles_on_unique_published_slot"

  def up
    execute <<~SQL
      WITH ranked_slots AS (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY site_id, slot_key
                 ORDER BY
                   CASE WHEN assignment_mode = 'manual' THEN 0 ELSE 1 END,
                   updated_at DESC,
                   id DESC
               ) AS slot_rank
        FROM site_articles
        WHERE status = 'published' AND slot_key IS NOT NULL
      )
      UPDATE site_articles
      SET slot_key = NULL,
          placement = 'latest',
          position = 0,
          updated_at = CURRENT_TIMESTAMP
      WHERE id IN (
        SELECT id FROM ranked_slots WHERE slot_rank > 1
      )
    SQL

    add_index :site_articles,
      [:site_id, :slot_key],
      unique: true,
      where: "status = 'published' AND slot_key IS NOT NULL",
      name: INDEX_NAME
  end

  def down
    remove_index :site_articles, name: INDEX_NAME
  end
end
