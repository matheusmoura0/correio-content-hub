class RegisterTurismoHoje < ActiveRecord::Migration[8.0]
  class MigrationSite < ActiveRecord::Base
    self.table_name = "sites"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  def up
    domain = "turismohoje.com.br"
    key = "turismo-hoje"
    conflict = MigrationSite.where(publication_key: key).where.not(domain: domain).exists?
    raise "A chave turismo-hoje já está vinculada a outro domínio" if conflict

    site = MigrationSite.find_or_initialize_by(domain: domain)
    site.assign_attributes(
      name: "Turismo Hoje",
      publication_key: key,
      active: true,
      site_type: "editorial",
      content_mode: "hub",
      layout_profile: "tourism",
      allowed_origins: "https://turismohoje.com.br\nhttps://www.turismohoje.com.br",
      updated_at: Time.current
    )
    site.created_at ||= Time.current
    site.save!

    {
      "destinos" => "Destinos",
      "roteiros" => "Roteiros",
      "hotelaria" => "Hotelaria",
      "gastronomia" => "Gastronomia",
      "experiencias" => "Experiências",
      "mobilidade" => "Aviação e mobilidade",
      "negocios" => "Turismo de negócios",
      "guia-do-viajante" => "Guia do viajante"
    }.each do |slug, name|
      category = MigrationCategory.find_or_initialize_by(site_id: site.id, slug: slug)
      category.name = name
      category.created_at ||= Time.current
      category.updated_at = Time.current
      category.save!
    end
  end

  def down
    # Preserva o site, as configurações e as matérias cadastradas.
  end
end