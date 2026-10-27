ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"

class ArticleImageTest < Minitest::Test
  BASE = "https://www.correiodamanha.com.br/noticia.html"

  def image(html)
    Web::ArticleImage.call(Nokogiri::HTML(html), base_url: BASE)
  end

  def test_placeholder_is_not_a_photo_and_twitter_can_supply_the_real_one
    assert_nil image('<meta property="og:image" content="/images/logo_600x450.jpg">')
    assert_equal "https://www.correiodamanha.com.br/_midias/photo.jpg", image('<meta property="og:image" content="/images/logo_600x450.jpg"><meta name="twitter:image" content="/_midias/photo.jpg">')
  end

  def test_only_article_images_are_read_from_structured_data
    html = '<script type="application/ld+json">{"@graph":[{"@type":"Organization","image":"/publisher.jpg"},{"@type":"NewsArticle","image":{"@type":"ImageObject","contentUrl":"/article.jpg"},"publisher":{"logo":{"url":"/logo.jpg"}}}]}</script>'
    assert_equal "https://www.correiodamanha.com.br/article.jpg", image(html)
  end

  def test_lazy_image_matching_the_article_title_is_a_safe_fallback
    html = '<h1>Notícia principal</h1><article><img alt="Correio" src="/imagens/correio-da-manha-linha-vermelha.png"><img alt="Notícia principal" data-src="/_midias/photo.jpg"></article>'
    assert_equal "https://www.correiodamanha.com.br/_midias/photo.jpg", image(html)
  end

  def test_related_news_is_not_used_for_an_article_without_a_photo
    html = '<h1>Turismo</h1><article><img alt="Turismo" src="/imagens/bg-640x410.jpg"><a href="/outra.html"><img alt="Outra notícia" src="/_midias/other.jpg"></a></article>'
    assert_nil image(html)
  end

  def test_invalid_protocols_and_malformed_json_are_ignored
    assert_nil image('<meta property="og:image" content="javascript:alert(1)"><script type="application/ld+json">{invalid}</script>')
    assert_nil Web::ArticleImage.normalize("data:image/png;base64,abc", base_url: BASE)
  end

  def test_image_can_be_extracted_without_a_long_article_body
    extractor = Web::ExtractArticle.new(BASE)
    extractor.define_singleton_method(:fetch) { |*| ['<meta property="og:image" content="/photo.jpg">', URI(BASE)] }
    assert_equal "https://www.correiodamanha.com.br/photo.jpg", extractor.image_url
  end

  def test_external_redirect_is_not_treated_as_an_authorized_correio_photo
    extractor = Web::ExtractArticle.new(BASE)
    extractor.define_singleton_method(:fetch) { |*| ['<meta property="og:image" content="/photo.jpg">', URI("https://external.example/news")] }
    assert_nil extractor.image_url
  end
end
