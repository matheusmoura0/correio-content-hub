admin_email = ENV.fetch("ADMIN_EMAIL", "admin@correio.local")
admin_password = ENV.fetch("ADMIN_PASSWORD", "changeme123")

admin = User.find_or_initialize_by(email: admin_email)
admin.name = ENV.fetch("ADMIN_NAME", "Administrador")
admin.role = "admin"
admin.password = admin_password
admin.password_confirmation = admin_password
admin.save!

site = Site.find_or_create_by!(domain: "correioeconomico.local") do |record|
  record.name = "Correio Econômico"
  record.active = true
end

Category.find_or_create_by!(site: site, slug: "economia") do |category|
  category.name = "Economia"
end



cinema_sites = [
  {
    name: "CINEMAGAZINE",
    domain: "revistacinemagazine.com.br",
    publication_key: "cinemagazine",
    site_type: "hybrid",
    content_mode: "hybrid",
    external_provider: "tmdb",
    layout_profile: "cinemagazine",
    categories: {
      "filmes" => "Filmes",
      "series" => "Séries",
      "streaming" => "Streaming",
      "trailers" => "Trailers",
      "noticias" => "Notícias",
      "listas" => "Listas"
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
    categories: {
      "critica" => "Crítica",
      "ensaios" => "Ensaios",
      "entrevistas" => "Entrevistas",
      "festivais" => "Festivais",
      "historia-do-cinema" => "História do Cinema",
      "industria" => "Indústria"
    }
  }
]

cinema_sites.each do |attributes|
  categories = attributes.delete(:categories)
  cinema_site = Site.find_or_initialize_by(domain: attributes[:domain])
  cinema_site.assign_attributes(attributes.merge(active: true))
  cinema_site.allowed_origins = [
    "https://#{attributes[:domain]}",
    "https://www.#{attributes[:domain]}"
  ].join("\n")
  cinema_site.save!

  categories.each do |slug, name|
    category = Category.find_or_initialize_by(site: cinema_site, slug:)
    category.name = name
    category.save!
  end
end

puts "Usuário local: #{admin_email}"


# Mantém o catálogo oficial de RSS e os monitoramentos por editoria
# sincronizados em todos os ambientes. O serviço é idempotente.
Correio::SyncRssCatalog.call
