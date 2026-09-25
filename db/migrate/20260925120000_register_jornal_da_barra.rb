class RegisterJornalDaBarra < ActiveRecord::Migration[8.0]
  class MigrationSite < ActiveRecord::Base
    self.table_name = "sites"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  def up
    domain = "jornaldabarra.com.br"
    key = "jornal-da-barra"
    conflict = MigrationSite.where(publication_key: key).where.not(domain: domain).exists?
    raise "A chave jornal-da-barra já está vinculada a outro domínio" if conflict

    site = MigrationSite.find_or_initialize_by(domain: domain)
    if site.new_record?
      site.assign_attributes(
        name: "Jornal da Barra",
        publication_key: key,
        active: true,
        site_type: "editorial",
        content_mode: "hub",
        layout_profile: "standard",
        allowed_origins: "https://jornaldabarra.com.br\nhttps://www.jornaldabarra.com.br"
      )
      site.save!
    else
      site.update!(
        name: "Jornal da Barra",
        publication_key: key,
        active: true,
        site_type: "editorial",
        content_mode: "hub",
        layout_profile: "standard",
        allowed_origins: "https://jornaldabarra.com.br\nhttps://www.jornaldabarra.com.br",
        updated_at: Time.current
      )
    end

    {
      "barra" => "Barra",
      "cidade" => "Cidade",
      "negocios" => "Negócios",
      "cultura" => "Cultura",
      "servicos" => "Serviços",
      "esportes" => "Esportes",
      "entretenimento" => "Entretenimento"
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
