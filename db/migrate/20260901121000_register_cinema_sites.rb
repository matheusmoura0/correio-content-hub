class RegisterCinemaSites < ActiveRecord::Migration[8.0]
  class MigrationSite < ActiveRecord::Base
    self.table_name = "sites"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  def up
    publications.each do |attributes|
      categories = attributes.delete(:categories)
      site = MigrationSite.find_or_initialize_by(domain: attributes[:domain])
      site.assign_attributes(attributes.merge(active: true, updated_at: Time.current))
      site.created_at ||= Time.current
      site.save!

      categories.each do |slug, name|
        category = MigrationCategory.find_or_initialize_by(site_id: site.id, slug:)
        category.name = name
        category.updated_at = Time.current
        category.created_at ||= Time.current
        category.save!
      end
    end
  end

  def down
    # Os conteúdos e configurações editoriais podem existir após o deploy.
    # O rollback de schema não remove dados de publicações automaticamente.
  end

  private

  def publications
    [
      {
        name: "CINEMAGAZINE",
        domain: "cinemagazine.com.br",
        publication_key: "cinemagazine",
        site_type: "hybrid",
        content_mode: "hybrid",
        external_provider: "tmdb",
        layout_profile: "cinemagazine",
        allowed_origins: "https://cinemagazine.com.br\nhttps://www.cinemagazine.com.br",
        categories: {
          "filmes" => "Filmes", "series" => "Séries", "streaming" => "Streaming",
          "trailers" => "Trailers", "noticias" => "Notícias", "listas" => "Listas"
        }
      },
      {
        name: "Jornal do Cinema",
        domain: "jornaldocinema.com.br",
        publication_key: "jornal-do-cinema",
        site_type: "editorial",
        content_mode: "hub",
        external_provider: nil,
        layout_profile: "cinema_journal",
        allowed_origins: "https://jornaldocinema.com.br\nhttps://www.jornaldocinema.com.br",
        categories: {
          "critica" => "Crítica", "ensaios" => "Ensaios", "entrevistas" => "Entrevistas",
          "festivais" => "Festivais", "historia-do-cinema" => "História do Cinema", "industria" => "Indústria"
        }
      }
    ]
  end
end
