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

puts "Usuário local: #{admin_email}"


# Mantém o catálogo oficial de RSS e os monitoramentos por editoria
# sincronizados em todos os ambientes. O serviço é idempotente.
Correio::SyncRssCatalog.call
