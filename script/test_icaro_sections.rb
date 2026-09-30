# Run with: ruby script/test_icaro_sections.rb
require_relative "../app/services/publishing/site_profile"
require_relative "../app/services/publishing/populate_site"

def check(condition, message)
  raise message unless condition
end

class SectionTestRelation
  attr_reader :rows
  def initialize(rows) = @rows = rows
  def where(**conditions)
    self.class.new(rows.select { |row| conditions.all? { |key, value| Array(value).include?(row[key]) } })
  end
  def distinct = self
  def count(key) = rows.map { |row| row[key] }.uniq.length
  def update_all(**values) = rows.each { |row| row.merge!(values) }
end

def Time.current = now unless Time.respond_to?(:current)

site = Struct.new(:id, :layout_profile, :site_articles).new(1, "icaro", nil)
profile = Publishing::SiteProfile.for(site)
sections = Publishing::SiteProfile::ICARO_SECTIONS.keys
slots = sections.flat_map { |slug| Publishing::SiteProfile.icaro_section_slots(slug) }
check(slots.length == 72 && slots.uniq.length == 72, "Six independent sections must have 12 unique slots each")
check((slots & profile.automatic_order).empty?, "Home automatic fill must not consume section slots")
check((slots - Publishing::SiteProfile.slot_keys(site)).empty?, "All section slots must be publishable")
check(Publishing::SiteProfile.slot_keys(site).include?("icaro_aviation_1"), "Manual aviation cover slot must be publishable")
check(Publishing::SiteProfile.icaro_section_slots("unknown").empty?, "Unknown category must have no slots")

rows = [
  {status: "published", assignment_mode: "automatic", slot_key: "hero"},
  {status: "published", assignment_mode: "automatic", slot_key: "section_icaro_destinos_1"},
  {status: "published", assignment_mode: "manual", slot_key: "section_icaro_destinos_2"},
  {status: "published", assignment_mode: "automatic", slot_key: "section_icaro_sabores_1"}
]
site.site_articles = SectionTestRelation.new(rows)
category = Struct.new(:site_id, :slug).new(1, "destinos")
service = Publishing::PopulateSite.new(site: site, scope: nil, category: category, target: "section")
section = Publishing::SiteProfile::Profile.new(key: "icaro", label: "Destinos", groups: {}, automatic_order: Publishing::SiteProfile.icaro_section_slots("destinos"))
check(service.send(:automatic_capacity, section) == 11, "Manual position must reduce available capacity")
service.send(:reset_automatic_slots!, section)
check(rows[1][:slot_key].nil?, "Selected section automatic slot must be released")
check(rows[0][:slot_key] == "hero", "Home must be preserved")
check(rows[2][:slot_key] == "section_icaro_destinos_2", "Manual slot must be preserved")
check(rows[3][:slot_key] == "section_icaro_sabores_1", "Other section must be preserved")
begin
  Publishing::PopulateSite.call(site: site, scope: nil, category: nil, target: "section")
  raise "Missing category was accepted"
rescue ArgumentError
end
puts "PASS: section capacity, isolation, manual preservation and category validation"
