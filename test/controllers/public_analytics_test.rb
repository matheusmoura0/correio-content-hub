ENV["RAILS_ENV"] = "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "action_dispatch/testing/integration"
require "warden/test/helpers"

class PublicAnalyticsTest < Minitest::Test
  include Warden::Test::Helpers

  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    Warden.test_mode!
    @site = Site.create!(name: "Correio da Manhã", domain: "correiodamanha.com.br",
      publication_key: "correio-da-manha", active: true)
    @other = Site.create!(name: "Outra publicação", domain: "other.example", publication_key: "other", active: true)
    @share = @site.create_analytics_share!
    @session = ActionDispatch::Integration::Session.new(Rails.application)
    @session.host! "www.example.com"
    @from = (Time.now.utc.to_date - 7).iso8601
    @to = (Time.now.utc.to_date - 1).iso8601
    event(@site, "Matéria do Correio", "Ana Repórter")
    event(@other, "Matéria confidencial de outro jornal", "Outro Autor")
  end

  def teardown
    Warden.test_reset!
    ActionController::Base.allow_forgery_protection = @forgery_protection
    ActiveRecord::Base.connection.rollback_transaction
  end

  def event(site, title, author)
    site.analytics_events.create!(content_key: "article-1", content_author: author, content_category: "Cultura",
      event_type: "page_view", occurred_at: 2.days.ago, page_title: title, path: "/materia",
      visitor_hash: "private-visitor", session_hash: "private-session", device_type: "mobile", value: 0,
      image_url: "https://cdn.example/news.jpg", author_image_url: "https://cdn.example/author.jpg")
  end

  def path(token = @share.token)
    "/audiencia/#{token}"
  end

  def request(method, url, params = {})
    @session.public_send(method, url, params: params, env: { "action_dispatch.show_exceptions" => :all })
  end

  def sign_in(role)
    @user ||= User.create!(email: "#{role}@example.com", password: "strong-password-123", role: role, name: "Editor")
    login_as @user, scope: :user
  end

  def test_without_login_shows_only_linked_publication_and_no_internal_data
    request(:get, path, site_id: @other.id, from: @from, to: @to)
    assert_equal 200, @session.response.status
    body = @session.response.body
    assert_equal "utf-8", Nokogiri::HTML(body).at_css("meta[charset]")["charset"]
    assert_includes body, "Matéria do Correio"
    assert_includes body, "Ana Repórter"
    assert_includes body, "https://cdn.example/news.jpg"
    ["Matéria confidencial", "Outro Autor", "private-visitor", "private-session", "Atividades recentes",
      "Compartilhar com a redação", "Instalar a tag", "insights-export", "Destinos mais clicados", "hub-sidebar"].each do |private_text|
      refute_includes body, private_text
    end
    assert_equal "no-referrer", @session.response.headers["Referrer-Policy"]
    assert_includes @session.response.headers["Cache-Control"], "no-store"
    assert_includes @session.response.headers["X-Robots-Tag"], "noindex"
    assert_equal "DENY", @session.response.headers["X-Frame-Options"]
    assert_equal 0, ActivityLog.count
    assert_includes body, "Exportar PDF"
  end

  def test_dimensions_drilldown_and_navigation_remain_public
    %w[articles authors categories].each do |dimension|
      request(:get, path, dimension: dimension, from: @from, to: @to)
      assert_equal 200, @session.response.status
      document = Nokogiri::HTML(@session.response.body)
      document.css(".insights-page a[href]").each do |link|
        assert link["href"].start_with?(path), "Internal navigation leaked: #{link['href']}"
      end
      assert_equal path, document.at_css(".insights-filters")["action"]
      refute document.at_css("select[name=site_id]")
    end
    request(:get, path, author: "Ana Repórter", article: "article-1", from: @from, to: @to)
    assert_includes @session.response.body, "Matéria do Correio"
    request(:get, path, author: "Outro Autor", from: @from, to: @to)
    assert_includes @session.response.body, "Nenhum resultado"
  end

  def test_pagination_and_limits
    26.times do |i|
      event(@site, "Conteúdo #{i}", "Ana Repórter")
      @site.analytics_events.order(:id).last.update!(content_key: "extra-#{i}")
    end
    request(:get, path, page: 2, per_page: 25, from: @from, to: @to)
    assert_equal 200, @session.response.status
    assert_equal 2, Nokogiri::HTML(@session.response.body).css(".insights-ranking tbody tr").size
    request(:get, path, from: (Time.now.utc.to_date - 365).iso8601, to: @to)
    assert_equal 200, @session.response.status
    assert_includes @session.response.body, "até 90 dias completos"
    request(:get, path, from: "invalid", to: "invalid", dimension: "sql", sort: "sql", per_page: 999)
    assert_equal 200, @session.response.status
  end

  def test_invalid_revoked_and_inactive_links_are_not_available
    request(:get, path("a" * 32))
    assert_equal 404, @session.response.status
    assert_includes @session.response.body, "Link indisponível"
    old = @share.token
    @share.regenerate_token
    request(:get, path(old))
    assert_equal 404, @session.response.status
    request(:get, path)
    assert_equal 200, @session.response.status
    @site.update!(active: false)
    request(:get, path)
    assert_equal 404, @session.response.status
    @share.destroy!
    request(:get, path)
    assert_equal 404, @session.response.status
  end

  def test_cannot_share_other_publications_even_with_existing_token
    refute @other.build_analytics_share.valid?
    @share.update_column(:site_id, @other.id)
    request(:get, path)
    assert_equal 404, @session.response.status
  end

  def test_management_requires_authentication_and_admin
    request(:post, "/metricas/compartilhamento", site_id: @site.id)
    assert_equal 302, @session.response.status
    assert_includes @session.response.location, "/users/sign_in"
    sign_in("member")
    old = @share.token
    request(:patch, "/metricas/compartilhamento", site_id: @site.id)
    assert_equal 302, @session.response.status
    assert_equal old, @share.reload.token
    request(:delete, "/metricas/compartilhamento", site_id: @site.id)
    assert AnalyticsShare.exists?(@share.id)
    request(:get, "/metricas", site_id: @site.id)
    assert_equal 200, @session.response.status
    refute_includes @session.response.body, @share.token
  end

  def test_admin_can_create_replace_and_revoke_but_not_share_other_sites
    sign_in("admin")
    request(:get, "/metricas", site_id: @site.id)
    assert_equal 200, @session.response.status
    assert_includes @session.response.body, path
    old = @share.token
    request(:post, "/metricas/compartilhamento", site_id: @site.id)
    assert_equal 1, AnalyticsShare.where(site: @site).count
    assert_equal old, @share.reload.token
    request(:patch, "/metricas/compartilhamento", site_id: @site.id)
    refute_equal old, @share.reload.token
    request(:get, path(old))
    assert_equal 404, @session.response.status
    request(:post, "/metricas/compartilhamento", site_id: @other.id)
    assert_equal 404, @session.response.status
    request(:delete, "/metricas/compartilhamento", site_id: @site.id)
    refute AnalyticsShare.exists?(@share.id)
    request(:post, "/metricas/compartilhamento", site_id: @site.id)
    assert_equal 1, AnalyticsShare.where(site: @site).count
    assert_equal 32, @site.reload.analytics_share.token.length
  end

  def test_private_metrics_and_exports_remain_authenticated
    ["/metricas", "/metricas/exportar.csv", "/metricas/exportar.json", "/metricas/exportar.pdf"].each do |url|
      request(:get, url, token: @share.token, site_id: @site.id)
      assert_includes [302, 401], @session.response.status
      assert_includes @session.response.location, "/users/sign_in" if @session.response.redirect?
      refute_includes @session.response.body, "Matéria do Correio"
    end
  end

  def test_link_cannot_change_state_and_post_still_requires_csrf
    old = @share.token
    request(:post, path, site_id: @site.id)
    assert_equal 404, @session.response.status
    assert_equal old, @share.reload.token
    sign_in("admin")
    ActionController::Base.allow_forgery_protection = true
    request(:delete, "/metricas/compartilhamento", site_id: @site.id)
    assert_equal 422, @session.response.status
    assert AnalyticsShare.exists?(@share.id)
  end

  def test_public_pdf_is_filtered_and_scoped_to_the_shared_site
    request(:get, "#{path}/exportar.pdf", site_id: @other.id, author: "Ana Repórter", from: @from, to: @to, page: 999)
    assert_equal 200, @session.response.status
    assert_equal "application/pdf", @session.response.media_type
    assert_includes @session.response.headers["Content-Disposition"], "attachment"
    assert_includes @session.response.headers["Cache-Control"], "no-store"
    assert @session.response.body.start_with?("%PDF-")
    text = IO.popen(["pdftotext", "-", "-"], "r+") { |io| io.write(@session.response.body); io.close_write; io.read }
    assert_includes text, "Matéria do Correio"
    assert_includes text, "Ana Repórter"
    assert_includes text, "Relatório de audiência"
    ["Matéria confidencial", "Outro Autor", "private-visitor", "private-session", @share.token].each { |value| refute_includes text, value }
    old = @share.token
    @share.regenerate_token
    request(:get, "#{path(old)}/exportar.pdf")
    assert_equal 404, @session.response.status
    @site.update!(active: false)
    request(:get, "#{path}/exportar.pdf")
    assert_equal 404, @session.response.status
  end

  def test_mobile_controls_preserve_filters_and_offer_matching_pdf_download
    request(:get, path, dimension: "authors", author: "Ana Repórter", q: "Ana", from: @from, to: @to, sort: "clicks")
    assert_equal 200, @session.response.status
    document = Nokogiri::HTML(@session.response.body)
    form = document.at_css(".audience-filter-form")
    assert_equal path, form["action"]
    assert_equal "authors", form.at_css("input[name=dimension]")["value"]
    assert_equal "Ana", form.at_css("input[name=q]")["value"]
    assert_equal "Ana Repórter", form.at_css("input[name=author]")["value"]
    assert_equal @from, form.at_css("input[name=from]")["value"]
    assert_equal @to, form.at_css("input[name=to]")["value"]
    assert_nil document.at_css(".audience-filter-options")["open"]
    assert document.at_css(".audience-active-filters a[aria-label='Remover filtro de assinatura']")
    links = document.css(".audience-mobile-tools a")
    assert_equal ["#analytics-summary", "#analytics-ranking"], links.first(2).map { |link| link["href"] }
    assert_equal document.at_css(".insights-pdf-button")["href"], links.last["href"]
    query = Rack::Utils.parse_nested_query(URI.parse(links.last["href"]).query)
    assert_equal "Ana Repórter", query["author"]
    assert_equal "authors", query["dimension"]
    assert_equal "clicks", query["sort"]
    assert_nil query["site_id"]
    assert document.at_css("#analytics-summary")
    assert document.at_css("#analytics-ranking")
  end

  def test_public_search_submits_all_filters_without_changing_publication
    request(:get, path, q: "Ana", dimension: "articles", site_id: @other.id, from: @from, to: @to)
    assert_equal 200, @session.response.status
    assert_includes @session.response.body, "Matéria do Correio"
    refute_includes @session.response.body, "Matéria confidencial"
    document = Nokogiri::HTML(@session.response.body)
    assert_equal 1, document.css("input[name=q]").size
    assert_nil document.at_css("input[name=page]")
    assert_equal 1, document.css("button[aria-label='Buscar matéria ou jornalista']").size
  end

  def test_columnist_ranking_uses_official_portraits_and_individual_drilldown
    profile = @site.analytics_author_profiles.create!(slug: "ana", name: "Ana Repórter",
      source_url: "https://www.correiodamanha.com.br/colunistas/ana",
      image_url: "https://www.correiodamanha.com.br/images/cm/colunistas/ana.jpg")
    event(@site, "Matéria compartilhada", "Ana Repórter e Bia")
    request(:get, path, dimension: "columnists", from: @from, to: @to)
    assert_equal 200, @session.response.status
    document = Nokogiri::HTML(@session.response.body)
    assert_equal 1, document.css(".insights-ranking tbody tr").size
    assert_equal profile.image_url, document.at_css(".insights-author-image img")["src"]
    assert_includes @session.response.body, "Assinatura individual"
    link = document.at_css(".insights-story-cell a")["href"]
    query = Rack::Utils.parse_nested_query(URI.parse(link).query)
    assert_equal profile.slug, query["columnist"]
    assert_equal "articles", query["dimension"]
    request(:get, link)
    assert_equal 200, @session.response.status
    assert_includes @session.response.body, "Matéria do Correio"
    refute_includes @session.response.body, "Matéria compartilhada"
    document = Nokogiri::HTML(@session.response.body)
    assert_equal profile.slug, document.at_css("input[name=columnist]")["value"]
    assert_includes document.at_css(".audience-active-filters").text, profile.name
    request(:get, "#{path}/exportar.pdf", dimension: "columnists", from: @from, to: @to)
    assert_equal 200, @session.response.status
    text = IO.popen(["pdftotext", "-", "-"], "r+") { |io| io.write(@session.response.body); io.close_write; io.read }
    assert_includes text, "Colunistas"
    assert_includes text, profile.name
    refute_includes text, "Ana Repórter e Bia"
  end
end
