class RegisterJornalDeTeatro < ActiveRecord::Migration[8.0]
  class MigrationSite < ActiveRecord::Base
    self.table_name = "sites"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  def up
    domain = "jornaldeteatro.rio.br"
    key = "jornal-de-teatro"
    conflict = MigrationSite.where(publication_key: key).where.not(domain: domain).exists?
    raise "A chave jornal-de-teatro já está vinculada a outro domínio" if conflict

    site = MigrationSite.find_or_initialize_by(domain: domain)
    site.assign_attributes(
      name: "Jornal de Teatro",
      publication_key: key,
      active: true,
      site_type: "editorial",
      content_mode: "hub",
      layout_profile: "theatre",
      allowed_origins: "https://jornaldeteatro.rio.br
https://www.jornaldeteatro.rio.br",
      updated_at: Time.current
    )
    site.created_at ||= Time.current
    site.save!

    {
      "em-cartaz" => "Em cartaz",
      "critica" => "Crítica",
      "bastidores" => "Bastidores",
      "agenda" => "Agenda",
      "entrevistas" => "Entrevistas"
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
