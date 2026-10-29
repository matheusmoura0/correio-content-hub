ENV["RAILS_ENV"] = "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "minitest/mock"
require "action_dispatch/testing/integration"
require "warden/test/helpers"

class AnalyticsEmailSchedulesTest < Minitest::Test
  include Warden::Test::Helpers

  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    Warden.test_mode!
    @site = Site.create!(name: "Correio da Manhã", domain: "correiodamanha.com.br", publication_key: "correio-da-manha", active: true)
    @user = User.create!(email: "admin@example.com", password: "strong-password-123", role: "admin", name: "Admin")
    @session = ActionDispatch::Integration::Session.new(Rails.application)
    @session.host! "www.example.com"
    @path = "/metricas/envio-semanal"
  end

  def teardown
    Warden.test_reset!
    ActionController::Base.allow_forgery_protection = @protection
    ActiveRecord::Base.connection.rollback_transaction
  end

  def request(method, suffix = "", params = {})
    @session.public_send(method, @path + suffix, params: { site_id: @site.id }.merge(params),
      env: { "action_dispatch.show_exceptions" => ActionController::Base.allow_forgery_protection ? :all : :none })
  end

  def test_only_admin_can_view_or_change_settings
    request(:get)
    assert_equal 302, @session.response.status
    assert_equal 0, AnalyticsEmailSchedule.count
    @user.update!(role: "member")
    login_as @user, scope: :user
    request(:patch, "", analytics_email_schedule: { recipients_text: "leak@example.com" })
    assert_equal 302, @session.response.status
    assert_equal 0, AnalyticsEmailSchedule.count
  end

  def test_admin_can_save_paused_recipients_and_view_history
    login_as @user, scope: :user
    request(:get)
    assert_equal 200, @session.response.status
    assert_includes @session.response.headers["Cache-Control"], "no-store"
    assert_includes @session.response.body, "relatorios@cm.com.br"
    request(:patch, "", analytics_email_schedule: { recipients_text: "one@example.com\ntwo@example.com", hour: 8, enabled: "0" })
    assert_equal 302, @session.response.status, Nokogiri::HTML(@session.response.body).at_css('[role="alert"]')&.text
    assert_equal %w[one@example.com two@example.com], AnalyticsEmailSchedule.sole.recipients
    refute AnalyticsEmailSchedule.sole.enabled?
    ActionController::Base.allow_forgery_protection = true
    request(:patch, "", analytics_email_schedule: { recipients_text: "evil@example.com" })
    assert_equal 422, @session.response.status
    assert_equal %w[one@example.com two@example.com], AnalyticsEmailSchedule.sole.recipients
  end

  def test_preview_requires_configuration_and_has_fixed_recipient_and_cooldown
    login_as @user, scope: :user
    request(:get)
    token = Nokogiri::HTML(@session.response.body).at_css("input[name=request_token]")["value"]
    Analytics::ReportEmailConfiguration.stub(:ready?, false) { request(:post, "/preview") }
    assert_equal 0, AnalyticsEmailDelivery.count
    Analytics::ReportEmailConfiguration.stub(:ready?, true) do
      2.times { request(:post, "/preview", recipient: "evil@example.com", request_token: token) }
    end
    assert_equal 1, AnalyticsEmailDelivery.count, "Response: #{@session.response.status}, #{@session.response.body.first(1000)}"
    assert_equal @user.email, AnalyticsEmailDelivery.sole.recipient
    assert_equal "pending", AnalyticsEmailDelivery.sole.status
    assert_empty ActionMailer::Base.deliveries
  end

  def token
    request(:get)
    Nokogiri::HTML(@session.response.body).at_css("input[name=request_token]")["value"]
  end

  def test_individual_recipient_management_is_validated_and_last_removal_pauses
    login_as @user, scope: :user
    @session.get(@path)
    assert_equal 200, @session.response.status, "Direct admin entry must default to Correio da Manhã"
    request(:post, "/add_recipient", email: " ONE@example.com ")
    assert_equal 302, @session.response.status
    request(:post, "/add_recipient", email: "one@example.com")
    assert_equal ["one@example.com"], AnalyticsEmailSchedule.sole.recipients
    request(:post, "/add_recipient", email: "bad\r\nBcc: leak@example.com")
    assert_equal 422, @session.response.status
    assert_equal ["one@example.com"], AnalyticsEmailSchedule.sole.recipients
    request(:post, "/add_recipient", email: "")
    assert_equal 422, @session.response.status
    Analytics::ReportEmailConfiguration.stub(:ready?, true) { AnalyticsEmailSchedule.sole.update!(enabled: true) }
    request(:delete, "/remove_recipient", email: "one@example.com")
    assert_equal 302, @session.response.status
    assert_empty AnalyticsEmailSchedule.sole.recipients
    refute AnalyticsEmailSchedule.sole.enabled?
  end

  def test_manual_send_uses_saved_recipients_selected_dates_and_one_use_token
    login_as @user, scope: :user
    nonce = token
    schedule = AnalyticsEmailSchedule.sole
    schedule.update!(recipients: %w[one@example.com two@example.com])
    from = (Time.now.utc.to_date - 3).iso8601
    to = Time.now.utc.to_date.iso8601
    Analytics::ReportEmailConfiguration.stub(:ready?, true) do
      2.times { request(:post, "/send_now", request_token: nonce, from: from, to: to, recipient: "evil@example.com") }
    end
    assert_equal 2, AnalyticsEmailDelivery.count
    assert_equal %w[one@example.com two@example.com], AnalyticsEmailDelivery.order(:recipient).pluck(:recipient)
    assert_equal [Date.iso8601(from)], AnalyticsEmailDelivery.distinct.pluck(:period_start)
    assert_equal [Date.iso8601(to)], AnalyticsEmailDelivery.distinct.pluck(:period_end)
    assert AnalyticsEmailDelivery.all.all? { |delivery| delivery.kind == "manual" }
    refute schedule.reload.enabled?
    assert_empty ActionMailer::Base.deliveries
    nonce = token
    Analytics::ReportEmailConfiguration.stub(:ready?, true) { request(:post, "/send_now", request_token: nonce, from: from, to: to) }
    assert_equal 2, AnalyticsEmailDelivery.count, "Cooldown must also apply to a fresh form token"
  end

  def test_manual_send_rejects_empty_recipients_bad_dates_and_forged_requests
    login_as @user, scope: :user
    nonce = token
    Analytics::ReportEmailConfiguration.stub(:ready?, true) do
      request(:post, "/send_now", request_token: nonce)
      assert_equal 0, AnalyticsEmailDelivery.count
      AnalyticsEmailSchedule.sole.update!(recipients: ["one@example.com"])
      today = Time.now.utc.to_date
      [["bad", today.iso8601], [(today + 1).iso8601, (today + 2).iso8601],
       [today.iso8601, (today - 1).iso8601], [(today - 90).iso8601, today.iso8601]].each do |from, to|
        request(:post, "/send_now", request_token: nonce, from: from, to: to)
        assert_equal 0, AnalyticsEmailDelivery.count
      end
      request(:post, "/send_now", request_token: "a" * 32)
      assert_equal 0, AnalyticsEmailDelivery.count
      ActionController::Base.allow_forgery_protection = true
      request(:post, "/send_now", request_token: nonce)
      assert_equal 422, @session.response.status
      assert_equal 0, AnalyticsEmailDelivery.count
    end
  end

  def test_manual_recipient_and_preview_endpoints_remain_admin_only
    @user.update!(role: "member")
    login_as @user, scope: :user
    %w[send_now preview add_recipient].each do |action|
      request(:post, "/#{action}", email: "leak@example.com")
      assert_equal 302, @session.response.status
    end
    request(:delete, "/remove_recipient", email: "leak@example.com")
    assert_equal 302, @session.response.status
    assert_equal 0, AnalyticsEmailSchedule.count
    assert_equal 0, AnalyticsEmailDelivery.count
  end
end
