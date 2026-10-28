ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"
require "minitest/mock"

class SyncColumnistsTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @site = Site.create!(name: "Correio da Manhã", domain: "correiodamanha.com.br", publication_key: "correio-da-manha", active: true)
    @home = Nokogiri::HTML(<<~HTML)
      <a href="/colunistas/tales-faria">Tales Faria</a>
      <a href="/colunistas/tales-faria" class="cm-home-columnist-link"><img class="cm-home-columnist-avatar" src="/_midias/tales.jpg"><h3>Tales Faria</h3><p>Última notícia</p></a>
      <a href="/colunistas/magnavita">Magnavita</a>
      <a href="/colunistas/brasilianas">William França</a>
      <a href="/colunistas/correio-bastidores">Correio Bastidores</a>
      <a href="/colunistas/tales-faria/2026/10/article.html"><img src="/_midias/news.jpg">Outra notícia</a>
      <a href="https://evil.example/colunistas/foreign">Estranho</a>
      <a href="https://attacker@www.correiodamanha.com.br/colunistas/fake">Falso</a>
    HTML
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def test_only_official_profile_portraits_are_collected_without_article_fallback
    fetch = lambda do |url|
      return @home if url == Correio::SyncColumnists::HOME
      return Nokogiri::HTML('<a class="legacy-editoria-columnist-avatar"><img src="/images/cm/colunistas/magnavita.png"></a>') if url.end_with?("magnavita")
      Nokogiri::HTML('<meta property="og:image" content="https://www.correiodamanha.com.br/_midias/news.jpg"><article><img src="/_midias/news.jpg"></article>')
    end
    sync = Correio::SyncColumnists.new
    result = sync.stub(:fetch_document, fetch) { sync.call(force: true, max_duration: 60) }
    assert_equal 4, result.updated
    assert_equal 0, result.failed
    tales = @site.analytics_author_profiles.find_by!(slug: "tales-faria")
    assert_equal "https://www.correiodamanha.com.br/_midias/tales.jpg", tales.image_url
    magnavita = @site.analytics_author_profiles.find_by!(slug: "magnavita")
    assert_equal "Cláudio Magnavita", magnavita.name
    assert_includes magnavita.aliases, "claudio magnavita"
    assert_includes magnavita.aliases, "magnavita"
    assert_nil @site.analytics_author_profiles.find_by!(slug: "brasilianas").image_url
    refute @site.analytics_author_profiles.find_by!(slug: "correio-bastidores").individual?
    assert_equal 3, @site.analytics_author_profiles.columnists.count
    refute @site.analytics_author_profiles.exists?(slug: "foreign")
    refute @site.analytics_author_profiles.exists?(slug: "fake")
  end

  def test_failed_portrait_fetch_still_creates_identity_and_preserves_existing_photo
    profile = @site.analytics_author_profiles.create!(slug: "magnavita", name: "Cláudio Magnavita", source_url: "https://www.correiodamanha.com.br/colunistas/magnavita", image_url: "https://www.correiodamanha.com.br/_midias/previous.jpg")
    sync = Correio::SyncColumnists.new
    fetch = ->(url) { url == Correio::SyncColumnists::HOME ? @home : raise("Temporarily unavailable") }
    result = sync.stub(:fetch_document, fetch) { sync.call(force: true, max_duration: 60) }
    assert_equal 4, result.updated
    assert_equal 3, result.failed
    assert_equal "https://www.correiodamanha.com.br/_midias/previous.jpg", profile.reload.image_url
    assert @site.analytics_author_profiles.exists?(slug: "brasilianas")
    result = sync.stub(:fetch_document, ->(*) { flunk "Must respect the refresh cooldown" }) { sync.call(force: false, max_duration: 60) }
    assert result.skipped
  end
end
