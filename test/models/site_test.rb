ENV["RAILS_ENV"] = "test"
require_relative "../../config/environment"
require "minitest/autorun"

class SiteTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def test_correio_da_manha_is_always_source_only
    site = Site.create!(
      name: "Correio da Manhã",
      domain: "www.correiodamanha.com.br",
      publication_key: "correio-da-manha",
      site_type: "editorial",
      content_mode: "external",
      layout_profile: "standard",
      receives_hub_content: true,
      active: true
    )

    refute site.receives_hub_content?
    refute site.publication_destination?
    refute_includes Site.publication_destinations, site
  end

  def test_active_hub_site_is_a_publication_destination
    token = SecureRandom.hex(6)
    site = Site.create!(
      name: "Destino #{token}",
      domain: "#{token}.example",
      publication_key: token,
      site_type: "editorial",
      content_mode: "hub",
      layout_profile: "standard",
      receives_hub_content: true,
      active: true
    )

    assert site.publication_destination?
    assert_includes Site.publication_destinations, site
  end

  def test_correio_economico_is_managed_by_cms_and_cannot_be_reactivated
    site = Site.create!(name: "Correio Econômico", domain: "correioeconomico.local",
      publication_key: "correio-economico", site_type: "editorial", content_mode: "hub",
      layout_profile: "standard", active: true, receives_hub_content: true)

    assert site.cms_managed?
    refute site.active?
    refute site.receives_hub_content?
    refute site.publication_destination?
    refute_includes Site.publication_destinations, site
    assert_equal "external", site.content_mode

    category = site.categories.create!(name: "Economia", slug: "economia")
    site.update!(active: true, receives_hub_content: true, content_mode: "hub")
    refute site.reload.active?
    assert_equal category, site.categories.first
  end

  def test_cms_ownership_is_recognized_by_domain_or_key
    by_domain = Site.new(name: "Registro antigo", domain: "https://www.correioeconomico.com.br/",
      publication_key: "economia", active: true, receives_hub_content: true)
    by_domain.valid?
    assert by_domain.cms_managed?
    refute by_domain.publication_destination?

    by_key = Site.new(name: "Registro antigo", domain: "legacy.example",
      publication_key: "correio-economico", active: true, receives_hub_content: true)
    assert by_key.cms_managed?
    refute by_key.publication_destination?
  end
end
