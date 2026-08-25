admin_email = ENV.fetch("ADMIN_EMAIL", "admin@correio.local")
admin_password = ENV.fetch("ADMIN_PASSWORD", "changeme123")

User.find_or_create_by!(email: admin_email) do |user|
  user.name = ENV.fetch("ADMIN_NAME", "Administrador")
  user.role = "admin"
  user.password = admin_password
  user.password_confirmation = admin_password
end

admin = User.find_by!(email: admin_email)
admin.update!(role: "admin", name: admin.name.presence || "Administrador")

site = Site.find_or_create_by!(domain: "correioeconomico.local") do |record|
  record.name = "Correio Econômico"
  record.active = true
end

Category.find_or_create_by!(site: site, slug: "economia") do |category|
  category.name = "Economia"
end

puts "Usuário local: #{admin_email}"
puts "Senha local: #{admin_password}"
