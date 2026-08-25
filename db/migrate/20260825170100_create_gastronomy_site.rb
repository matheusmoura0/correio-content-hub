class CreateGastronomySite < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      INSERT INTO sites (name, domain, active, created_at, updated_at)
      VALUES ('Revista de Gastronomia', 'revistadegastronomia.com.br', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT (domain) DO NOTHING;

      INSERT INTO categories (site_id, name, slug, created_at, updated_at)
      SELECT sites.id, values.name, values.slug, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM sites
      CROSS JOIN (VALUES
        ('Receitas', 'receitas'),
        ('Restaurantes', 'restaurantes'),
        ('Tendências', 'tendencias'),
        ('Viagens', 'viagens'),
        ('Bebidas', 'bebidas'),
        ('Curiosidades', 'curiosidades')
      ) AS values(name, slug)
      WHERE sites.domain = 'revistadegastronomia.com.br'
      ON CONFLICT (site_id, slug) DO NOTHING;
    SQL
  end

  def down
    # Preserva o site e as matérias caso a estrutura seja revertida.
  end
end
