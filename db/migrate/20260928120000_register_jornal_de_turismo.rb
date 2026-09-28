class RegisterJornalDeTurismo < ActiveRecord::Migration[8.0]
  class MigrationSite < ActiveRecord::Base
    self.table_name = "sites"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  def up
    domain = "jornaldeturismo.tur.br"
    key = "jornal-de-turismo"
    conflict = MigrationSite.where(publication_key: key).where.not(domain: domain).exists?
    raise "A chave jornal-de-turismo já está vinculada a outro domínio" if conflict

    site = MigrationSite.find_or_initialize_by(domain: domain)
    site.assign_attributes(
      name: "Jornal de Turismo",
      publication_key: key,
      active: true,
      site_type: "editorial",
      content_mode: "hub",
      layout_profile: "tourism",
      allowed_origins: "https://jornaldeturismo.tur.br
https://www.jornaldeturismo.tur.br",
      updated_at: Time.current
    )
    site.created_at ||= Time.current
    site.save!

    {
      "destinos" => "Destinos",
      "aviacao" => "Aviação",
      "hotelaria" => "Hotelaria",
      "sabores" => "Sabores",
      "roteiros" => "Roteiros",
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
