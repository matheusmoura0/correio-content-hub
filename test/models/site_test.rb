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
end
