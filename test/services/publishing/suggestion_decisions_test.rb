ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"

class SuggestionDecisionsTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    token = SecureRandom.hex(8)
    @admin = User.create!(email: "admin-#{token}@example.com", password: "test-password", role: "admin", name: "Editor")
    @member = User.create!(email: "member-#{token}@example.com", password: "test-password", role: "member")
    @site = Site.create!(name: "Turismo #{token}", domain: "#{token}.example", publication_key: token,
      site_type: "editorial", content_mode: "hub", layout_profile: "tourism", receives_hub_content: true,
      editorial_keywords: "turismo", active: true)
    @category = @site.categories.create!(name: "Notícias", slug: "noticias")
    @feed = @site.feeds.create!(name: "Redação", url: "https://hub.cm.com.br/origens/#{token}", active: false)
    @articles = 2.times.map do |index|
      @feed.articles.create!(title: "Turismo #{index}", source_url: "https://#{token}.example/#{index}",
        content: "Reportagem sobre turismo e destinos. " * 20, status: "reviewing", published_at: Time.current)
    end
    @edition = Publishing::PrepareEdition.call(@site)
    @items = @edition.items.order(:id).to_a
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def approve(items, user: @admin, page_digest: @edition.reload.page_digest, categories: nil)
    Publishing::ApproveEdition.call(edition: @edition, user:, item_ids: items.map(&:id),
      categories: categories || items.to_h { |item| [item.id.to_s, @category.id] }, page_digest:,
      article_digests: items.to_h { |item| [item.id.to_s, item.article_digest] })
  end

  def reject(items)
    Publishing::RejectSuggestions.call(edition: @edition, user: @admin, item_ids: items.map(&:id),
      article_digests: items.to_h { |item| [item.id.to_s, item.article_digest] })
  end

  def test_single_approval_keeps_other_suggestions_pending
    approve([@items.first])
    assert_equal "ready", @edition.reload.status
    assert_equal "approved", @items.first.reload.decision
    assert_equal 1, @edition.items.pending.count
    assert_equal 1, @site.site_articles.where(status: "published").count
    approve([@items.last])
    assert_equal "approved", @edition.reload.status
  end

  def test_rejection_is_audited_and_does_not_return_in_this_product
    reject(@items)
    assert_equal "rejected", @edition.reload.status
    assert_equal @admin, @items.first.reload.decided_by
    assert @items.first.decided_at
    assert_nil Publishing::PrepareEdition.call(@site)
    assert_equal 0, @site.site_articles.where(status: "published").count
    other = @site.dup
    other.domain = "other-#{@site.domain}"
    other.publication_key = "other-#{@site.publication_key}"
    other.save!
    other.categories.create!(name: "Notícias", slug: "noticias")
    assert_equal 2, Publishing::PrepareEdition.call(other).items.count
  end

  def test_rejection_after_approval_does_not_overwrite_approval_audit
    approve([@items.first])
    approval_time = @edition.reload.approved_at
    reject([@items.last])
    assert_equal "approved", @edition.reload.status
    assert_equal approval_time, @edition.approved_at
    assert_equal @admin, @edition.approved_by
  end

  def test_member_cannot_approve_or_reject
    assert_raises(ArgumentError) { approve([@items.first], user: @member) }
    assert_raises(ArgumentError) do
      Publishing::RejectSuggestions.call(edition: @edition, user: @member, item_ids: [@items.first.id], article_digests: {})
    end
    assert_equal 2, @edition.items.pending.count
  end

  def test_old_screen_cannot_publish_after_another_decision
    old_digest = @edition.page_digest
    approve([@items.first])
    assert_raises(ArgumentError) { approve([@items.last], page_digest: old_digest) }
    assert_equal "pending", @items.last.reload.decision
  end

  def test_batch_with_invalid_category_publishes_nothing
    assert_raises(ArgumentError) { approve(@items, categories: { @items.first.id.to_s => @category.id }) }
    assert_equal 0, @site.site_articles.where(status: "published").count
    assert_equal 2, @edition.items.pending.count
  end

  def test_worker_replaces_changed_suggestions_without_publishing
    @items.first.article.update!(title: "Turismo atualizado")
    replacement = Publishing::PrepareEdition.call(@site)
    assert_equal "expired", @edition.reload.status
    refute_equal @edition.id, replacement.id
    assert_equal 0, @site.site_articles.where(status: "published").count
  end

  def test_import_stages_content_without_publishing_or_changing_approved_distribution
    importer = Rss::ImportFeed.new(@feed)
    importer.send(:distribute, @items.first.article)
    distribution = @site.site_articles.find_by!(article: @items.first.article)
    assert_equal "draft", distribution.status
    approve([@items.first])
    published_at = distribution.reload.published_at
    importer.send(:distribute, @items.first.article)
    assert_equal "published", distribution.reload.status
    assert_equal published_at, distribution.published_at
    assert_equal 1, @site.site_articles.where(status: "published").count
  end

  def test_incomplete_and_future_content_are_not_suggested
    @articles.first.update!(content: "Resumo curto")
    @articles.last.update!(published_at: 1.day.from_now)
    assert_nil Publishing::PrepareEdition.call(@site)
    assert_equal "expired", @edition.reload.status
  end

  def test_manual_position_is_not_overwritten
    other = @feed.articles.create!(title: "Turismo manual", source_url: "https://#{@site.domain}/manual",
      content: "Reportagem sobre turismo. " * 20, status: "reviewing")
    Publishing::PublishArticle.call(article: other, site: @site, category: @category, slot_key: @items.first.slot_key)
    assert_raises(ArgumentError) { approve([@items.first]) }
    replacement = Publishing::PrepareEdition.call(@site)
    refute_includes replacement.items.pluck(:slot_key), @items.first.slot_key
    assert_equal other.id, @site.site_articles.find_by!(slot_key: @items.first.slot_key, status: "published").article_id
  end
end
