ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"
require "minitest/mock"
require "stringio"

class ImportFeedTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    token = SecureRandom.hex(8)
    @feed = Feed.create!(name: "Fonte #{token}", url: "https://www.correiodamanha.com.br/test-#{token}.xml")
    @entry = Rss::ImportFeed::DiscoveredEntry.new(url: "https://www.correiodamanha.com.br/#{token}.html",
      entry_id: token, title: "Cinema em destaque", summary: "Resumo", content: "Curto", published: Time.current)
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def import_with(extraction, image: nil)
    parsed = Struct.new(:entries).new([@entry])
    URI.stub(:open, StringIO.new("rss")) do
      Feedjira.stub(:parse, parsed) do
        Web::ExtractArticle.stub(:call, extraction) do
          Web::ExtractArticle.stub(:image_url, image) { Rss::ImportFeed.call(@feed) }
        end
      end
    end
  end

  def test_complete_articles_are_not_extracted_again
    article = @feed.articles.create!(title: @entry.title, source_url: @entry.url, content: "Texto editorial completo. " * 20,
      image_url: "https://www.correiodamanha.com.br/_midias/photo.jpg", image_source_url: @entry.url,
      image_license: "owned", image_rights_confirmed_at: Time.current)
    result = import_with(->(*) { raise "Extraction must not run for complete content" })
    assert_equal 0, result.warnings
    assert_equal 1, result.skipped
    assert_nil article.reload.source_enrichment_attempted_at
  end

  def test_failed_extraction_is_visible_and_uses_a_retry_cooldown
    result = import_with(->(*) { raise "Página respondeu com HTTP 403" })
    assert_equal 1, result.imported
    assert_equal 1, result.warnings
    article = Article.find_by!(source_url: @entry.url)
    assert article.source_enrichment_attempted_at
    assert_equal 1, @feed.reload.last_import_warning_count

    calls = 0
    result = import_with(->(*) { calls += 1; raise "Must wait for cooldown" })
    assert_equal 0, calls
    assert_equal 1, result.warnings
    article.update_column(:source_enrichment_attempted_at, 7.hours.ago)
    extracted = Web::ExtractArticle::Result.new(title: @entry.title, content: "Texto completo. " * 30,
      description: "Resumo completo", image_url: nil, author: "Redação", published_at: @entry.published)
    result = import_with(extracted)
    assert_equal 0, result.warnings
    assert_operator article.reload.content.length, :>, 150
    assert_equal 0, @feed.reload.last_import_warning_count
  end

  def test_enrichment_timestamps_do_not_invalidate_editorial_content
    article = @feed.articles.create!(title: @entry.title, source_url: @entry.url, content: "Texto completo. " * 30)
    digest = EditorialEdition.article_digest(article)
    article.update!(source_enrichment_attempted_at: Time.current)
    assert_equal digest, EditorialEdition.article_digest(article)
  end

  def test_complete_text_does_not_prevent_recovery_of_a_placeholder_photo
    article = @feed.articles.create!(title: @entry.title, source_url: @entry.url, content: "Texto completo. " * 30,
      image_url: "https://www.correiodamanha.com.br/images/logo_600x450.jpg", image_source_url: @entry.url,
      original_image_url: "https://www.correiodamanha.com.br/images/logo_600x450.jpg",
      image_license: "owned", image_rights_confirmed_at: Time.current)
    photo = "https://www.correiodamanha.com.br/_midias/photo.jpg"
    result = import_with(->(*) { raise "Do not replace complete text" }, image: photo)
    assert_equal 0, result.warnings
    assert_equal photo, article.reload.image_url
    assert_equal photo, article.original_image_url
    assert_equal "Texto completo. " * 30, article.content
  end
end
