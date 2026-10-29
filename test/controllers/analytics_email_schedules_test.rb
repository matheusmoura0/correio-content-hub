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
    @session.public_send(method, @path + suffix, params: { site_id: @site.id }.merge(params))
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
    assert_equal 302, @session.response.status
    assert_equal %w[one@example.com two@example.com], AnalyticsEmailSchedule.sole.recipients
    refute AnalyticsEmailSchedule.sole.enabled?
    ActionController::Base.allow_forgery_protection = true
    request(:patch, "", analytics_email_schedule: { recipients_text: "evil@example.com" })
    assert_equal 422, @session.response.status
    assert_equal %w[one@example.com two@example.com], AnalyticsEmailSchedule.sole.recipients
  end

  def test_preview_requires_configuration_and_has_fixed_recipient_and_cooldown
    login_as @user, scope: :user
    Analytics::ReportEmailConfiguration.stub(:ready?, false) { request(:post, "/preview") }
    assert_equal 0, AnalyticsEmailDelivery.count
    Analytics::ReportEmailConfiguration.stub(:ready?, true) do
      2.times { request(:post, "/preview", recipient: "evil@example.com") }
    end
    assert_equal 1, AnalyticsEmailDelivery.count
    assert_equal @user.email, AnalyticsEmailDelivery.sole.recipient
    assert_equal "pending", AnalyticsEmailDelivery.sole.status
    assert_empty ActionMailer::Base.deliveries
  end
end
