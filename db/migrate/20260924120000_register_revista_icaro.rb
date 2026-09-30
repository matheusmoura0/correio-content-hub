class RegisterRevistaIcaro < ActiveRecord::Migration[8.0]
  class MigrationSite < ActiveRecord::Base
    self.table_name = "sites"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  def up
    domain = "revistaicaro.com.br"
    key = "revista-icaro"
    conflict = MigrationSite.where(publication_key: key).where.not(domain: domain).exists?
    raise "A chave revista-icaro já está vinculada a outro domínio" if conflict

    site = MigrationSite.find_or_initialize_by(domain: domain)
    if site.new_record?
      site.assign_attributes(name: "Revista Ícaro", publication_key: key, active: true,
        site_type: "editorial", content_mode: "hub", layout_profile: "icaro",
        allowed_origins: "https://revistaicaro.com.br\nhttps://www.revistaicaro.com.br")
      site.save!
    elsif site.publication_key != key || site.layout_profile != "icaro"
      raise "Revista Ícaro já cadastrada com outra chave ou perfil; revise antes de migrar"
    end

    { "destinos" => "Destinos", "roteiros" => "Roteiros", "hospedagem" => "Hospedagem",
      "sabores" => "Sabores", "aviacao" => "Aviação", "guia-do-viajante" => "Guia do viajante" }.each do |slug, name|
      MigrationCategory.find_or_create_by!(site_id: site.id, slug: slug) { |category| category.name = name }
    end
  end

  def down
    # Preserva a publicação, as configurações e as matérias cadastradas.
  end
end
