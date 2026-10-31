ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"
require "minitest/mock"

class WeeklyReportsTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @env = %w[SMTP_ADDRESS SMTP_USERNAME SMTP_PASSWORD SMTP_PORT].to_h { |key| [key, ENV[key]] }
    ENV.update("SMTP_ADDRESS" => "smtp.resend.com", "SMTP_USERNAME" => "resend", "SMTP_PASSWORD" => "test-not-a-real-key", "SMTP_PORT" => "465")
    @site = Site.create!(name: "Correio da Manhã", domain: "correiodamanha.com.br", publication_key: "correio-da-manha", active: true)
    @schedule = AnalyticsEmailSchedule.create!(site: @site, recipients: ["one@example.com", "two@example.com"], enabled: true)
    @now = Time.utc(2026, 11, 2, 11, 0, 0)
    ActionMailer::Base.deliveries.clear
  end

  def teardown
    @env.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    ActionMailer::Base.deliveries.clear
    ActiveRecord::Base.connection.rollback_transaction
  end

  def run_cycle(now = @now)
    pdf = Struct.new(:data) { def call = data }.new("%PDF-fake-unit-test")
    Analytics::PdfReport.stub(:new, ->(*) { pdf }) { Analytics::SendWeeklyReports.call(now: now) }
  end

  def test_schedule_boundaries_and_previous_full_utc_week
    assert_nil @schedule.due_period(@now - 1.second)
    assert_equal Date.new(2026, 10, 26), @schedule.due_period(@now)
    assert_equal Date.new(2026, 10, 26), @schedule.due_period(@now + 5.days)
    assert_equal Date.new(2026, 11, 2), @schedule.due_period(@now + 7.days)
    run_cycle(@now - 1.second)
    assert_empty ActionMailer::Base.deliveries
    run_cycle
    run_cycle(@now + 1.hour)
    assert_equal 2, @schedule.deliveries.count
    assert_equal 2, ActionMailer::Base.deliveries.size, @schedule.deliveries.pluck(:status, :error_code).inspect
    assert_equal ["accepted"], @schedule.deliveries.distinct.pluck(:status)
    mail = ActionMailer::Base.deliveries.first
    assert_equal ["relatorios@cm.com.br"], mail.from
    assert_equal ["one@example.com"], mail.to
    assert_nil mail.cc
    assert_nil mail.bcc
    assert_includes mail.subject, "26/10/2026 a 01/11/2026"
    assert_equal "application/pdf", mail.attachments.first.mime_type
    assert_equal "%PDF-fake-unit-test", mail.attachments.first.decoded
    assert mail["Resend-Idempotency-Key"].value.start_with?("hub-weekly-")
    run_cycle(@now + 7.days)
    assert_equal 4, ActionMailer::Base.deliveries.size
  end

  def test_settings_normalize_validate_and_require_configuration
    @schedule.recipients_text = " ONE@example.com; one@example.com\nnew@example.com "
    @schedule.save!
    assert_equal %w[one@example.com new@example.com], @schedule.recipients
    @schedule.recipients = ["a@example.com\r\nBcc: leak@example.com"]
    refute @schedule.valid?
    @schedule.recipients = 31.times.map { |i| "#{i}@example.com" }
    refute @schedule.valid?
    @schedule.recipients = []
    refute @schedule.valid?
    @schedule.enabled = false
    assert @schedule.valid?
    ENV.delete("SMTP_PASSWORD")
    @schedule.enabled = true
    @schedule.recipients = ["one@example.com"]
    refute @schedule.valid?
    run_cycle
    assert_empty ActionMailer::Base.deliveries
    assert_equal 0, @schedule.deliveries.count
  end

  def test_pause_removal_and_inactive_sites_cancel_or_skip_work
    pending = @schedule.deliveries.create!(period_start: Date.new(2026, 10, 26), recipient: "removed@example.com")
    @schedule.update!(enabled: false)
    run_cycle
    assert_equal "cancelled", pending.reload.status
    assert_empty ActionMailer::Base.deliveries
    @schedule.update!(enabled: true)
    @site.update!(active: false)
    run_cycle
    assert_empty ActionMailer::Base.deliveries
  end

  def test_smtp_rejection_retries_but_ambiguous_result_does_not
    @schedule.update!(recipients: ["one@example.com"])
    failing = Object.new
    def failing.deliver_now = raise(Net::SMTPServerBusy, "temporary")
    AnalyticsReportMailer.stub(:weekly, failing) { run_cycle }
    item = @schedule.deliveries.sole
    assert_equal "retry", item.status
    assert_equal 1, item.attempts
    run_cycle(@now + 5.minutes)
    assert_empty ActionMailer::Base.deliveries
    run_cycle(@now + 31.minutes)
    assert_equal "accepted", item.reload.status, item.error_code
    assert_equal 2, item.attempts
    @schedule.deliveries.delete_all
    def failing.deliver_now = raise(IOError, "network details must not be stored")
    AnalyticsReportMailer.stub(:weekly, failing) { run_cycle }
    item = @schedule.deliveries.reload.sole
    assert_equal "uncertain", item.status
    assert_equal "IOError", item.error_code
    run_cycle(@now + 2.hours)
    assert_equal 1, item.reload.attempts
  end

  def test_temporary_rejections_stop_after_three_attempts
    @schedule.update!(recipients: ["one@example.com"])
    failing = Object.new
    def failing.deliver_now = raise(Net::SMTPServerBusy, "temporary")
    AnalyticsReportMailer.stub(:weekly, failing) do
      4.times { |i| run_cycle(@now + i.hours) }
    end
    item = @schedule.deliveries.sole
    assert_equal "failed", item.status
    assert_equal 3, item.attempts
    assert_equal "Net::SMTPServerBusy", item.error_code
  end

  def test_preview_can_send_while_paused_but_claimed_records_never_resend
    @schedule.update!(enabled: false)
    preview = @schedule.deliveries.create!(period_start: Date.new(2026, 10, 26), recipient: "admin@example.com", run_key: "preview-123")
    claimed = @schedule.deliveries.create!(period_start: Date.new(2026, 10, 26), recipient: "claimed@example.com", run_key: "preview-456", status: "sending", attempts: 1)
    run_cycle
    assert_equal "accepted", preview.reload.status, preview.error_code
    assert_equal "sending", claimed.reload.status
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_includes ActionMailer::Base.deliveries.first.subject, "Prévia"
  end

  def test_manual_send_works_while_paused_but_skips_removed_recipients
    @schedule.update!(enabled: false)
    start = Date.new(2026, 10, 22)
    item = @schedule.deliveries.create!(period_start: start, period_end: start + 2,
      recipient: "one@example.com", run_key: "manual-one")
    removed = @schedule.deliveries.create!(period_start: start, period_end: start + 2,
      recipient: "removed@example.com", run_key: "manual-one")
    run_cycle
    assert_equal "accepted", item.reload.status
    assert_equal "cancelled", removed.reload.status
    assert_equal 1, ActionMailer::Base.deliveries.size
    mail = ActionMailer::Base.deliveries.first
    assert_includes mail.subject, "Relatório de audiência | 22/10/2026 a 24/10/2026"
    refute_includes mail.subject, "Prévia"
    assert_includes mail.attachments.first.filename, "2026-10-22-2026-10-24"
    assert_equal "Manual", item.kind_label
    refute @schedule.reload.enabled?
  end

  def test_delivery_period_validation_and_legacy_weekly_fallback
    item = @schedule.deliveries.new(period_start: Date.new(2026, 10, 19), recipient: "one@example.com", run_key: "weekly")
    assert_equal Date.new(2026, 10, 25), item.report_end
    item.period_end = item.period_start - 1
    refute item.valid?
    item.period_end = item.period_start + 90
    refute item.valid?
    item.period_end = item.period_start + 89
    assert item.valid?
  end

  def test_pdf_generation_keeps_different_end_dates_separate
    @schedule.update!(enabled: false)
    start = Date.new(2026, 10, 19)
    %w[one@example.com two@example.com].each_with_index do |recipient, index|
      @schedule.deliveries.create!(period_start: start, period_end: start + index + 1,
        recipient: recipient, run_key: "manual-period-test")
    end
    periods = []
    pdf = Struct.new(:data) { def call = data }.new("%PDF-unit-test")
    Analytics::PdfReport.stub(:new, ->(report) { periods << [report.from.to_date, report.to.to_date]; pdf }) do
      Analytics::SendWeeklyReports.call(now: @now)
    end
    assert_equal [[start, start + 2], [start, start + 3]], periods
    assert_equal 2, ActionMailer::Base.deliveries.size
  end
end
