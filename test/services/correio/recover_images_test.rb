ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"
require "minitest/mock"

class RecoverImagesTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    token = SecureRandom.hex(8)
    @feed = Feed.create!(name: "Correio", url: "https://www.correiodamanha.com.br/test-#{token}.xml")
    @article = @feed.articles.create!(title: "Cinema", content: "Texto original. " * 30, status: "published",
      source_url: "https://www.correiodamanha.com.br/#{token}.html",
      image_url: "https://www.correiodamanha.com.br/images/logo_600x450.jpg",
      image_license: "owned", image_source_url: "https://www.correiodamanha.com.br/#{token}.html",
      image_rights_confirmed_at: Time.current)
    @photo = "https://www.correiodamanha.com.br/_midias/photo.jpg"
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def test_recovers_only_photo_fields_and_preserves_publication_state
    before = @article.attributes.except("image_url", "original_image_url", "image_source_url", "image_author", "image_license", "image_rights_confirmed_at", "source_enrichment_attempted_at", "updated_at")
    result = Web::ExtractArticle.stub(:image_url, @photo) { Correio::RecoverImages.recover(@article) }
    assert_equal :recovered, result
    assert_equal @photo, @article.reload.image_url
    assert_equal before, @article.attributes.slice(*before.keys)
    assert @article.licensed_image_ready?
  end

  def test_external_sources_and_manually_reviewed_images_are_not_changed
    @article.update!(source_url: "https://external.example/news")
    assert_equal :skipped, Correio::RecoverImages.recover(@article)
    @article.update!(source_url: "https://www.correiodamanha.com.br/news", image_license: "authorized", image_author: "Fotógrafo")
    assert_equal :skipped, Correio::RecoverImages.recover(@article)
  end

  def test_absent_photos_are_not_replaced_with_unrelated_or_placeholder_images
    result = Web::ExtractArticle.stub(:image_url, "https://www.correiodamanha.com.br/images/logo_600x450.jpg") { Correio::RecoverImages.recover(@article) }
    assert_equal :unavailable, result
    assert_nil @article.reload.editorial_image_url
    assert @article.source_enrichment_attempted_at
  end

  def test_failed_requests_keep_the_existing_record_and_record_a_cooldown
    result = Web::ExtractArticle.stub(:image_url, ->(*) { raise "HTTP 403" }) { Correio::RecoverImages.recover(@article) }
    assert_equal :failed, result
    assert_equal "published", @article.reload.status
    assert @article.source_enrichment_attempted_at
  end

  def test_a_photo_chosen_during_extraction_is_not_overwritten
    replacement = "https://www.correiodamanha.com.br/_midias/editor-choice.jpg"
    result = Web::ExtractArticle.stub(:image_url, ->(*) { @article.update!(image_url: replacement); @photo }) { Correio::RecoverImages.recover(@article) }
    assert_equal :skipped, result
    assert_equal replacement, @article.reload.image_url
  end

  def test_explicit_editor_image_review_is_preserved
    editor = User.create!(email: "photo-#{SecureRandom.hex(8)}@example.com", password: "test-password", role: "admin")
    @article.update!(image_rights_confirmed_by: editor)
    assert_equal :skipped, Correio::RecoverImages.recover(@article)
  end

  def test_batch_selects_published_articles_and_does_not_reprocess_repaired_images
    token = SecureRandom.hex(8)
    site = Site.create!(name: "Cinema #{token}", domain: "#{token}.example", publication_key: token,
      site_type: "editorial", content_mode: "hub", layout_profile: "cinema_journal", active: true)
    site.site_articles.create!(article: @article, status: "published")
    result = Web::ExtractArticle.stub(:image_url, @photo) { Correio::RecoverImages.call(limit: 10) }
    assert_equal 1, result.examined
    assert_equal 1, result.recovered
    assert_equal @photo, @article.reload.image_url
    assert_equal 0, Correio::RecoverImages.call(limit: 10).examined
  end
end
