ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"

class EditorialPolicyTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    token = SecureRandom.hex(8)
    @site = Site.create!(name: "Cinema #{token}", domain: "#{token}.example", publication_key: token,
      site_type: "editorial", content_mode: "hub", layout_profile: "cinemagazine", active: true)
    @feed = Feed.create!(name: "Últimas notícias", url: "https://www.correiodamanha.com.br/test-#{token}.xml")
    @policy = Publishing::EditorialPolicy.new(@site)
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def article(title, description)
    @feed.articles.create!(title:, description:, source_url: "https://www.correiodamanha.com.br/#{SecureRandom.hex(10)}")
  end

  def test_non_screen_meanings_of_series_are_not_cinema_evidence
    refute @policy.eligible?(article("GP de São Paulo", "Interlagos terá uma série de novidades"))
    refute @policy.eligible?(article("Polícia investiga 19 corpos", "Investigação descarta assassino em série"))
    assert @policy.eligible?(article("Apple TV lança Noturno", "Nova série estreia com dez episódios"))
  end

  def test_oscar_needs_award_or_film_context
    refute @policy.eligible?(article("Primeiro gol após Oscar", "O jogador marcou no campeonato estadual"))
    assert @policy.eligible?(article("Oscar anuncia indicados", "Prêmio celebra o melhor ator"))
    assert @policy.eligible?(article("Filme brasileiro estreia", "Longa de um novo cineasta"))
  end

  def test_worker_replaces_suggestions_that_no_longer_match_policy
    @site.update!(editorial_keywords: "serie", layout_profile: "standard")
    item = article("GP de São Paulo", "Uma série de novidades")
    item.update!(content: "Detalhes da corrida e da programação esportiva. " * 10)
    @site.categories.create!(name: "Notícias", slug: "noticias")
    edition = Publishing::PrepareEdition.call(@site)
    assert edition
    @site.update!(layout_profile: "cinemagazine")
    assert_nil Publishing::PrepareEdition.call(@site)
    assert_equal "expired", edition.reload.status
  end
end
