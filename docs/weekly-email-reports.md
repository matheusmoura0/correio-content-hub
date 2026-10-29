# Weekly email reports

Admin entry: Metrics > Relatório semanal por e-mail. Only the active Correio
da Manhã is supported. Settings and recipient history require an admin login;
they are never exposed on public dashboards. New schedules default to paused.

## Sender setup

Use a transactional sending provider, not an SMTP server installed on this VPS.
The sender is fixed to `Correio da Manhã <relatorios@cm.com.br>`.
For Resend:

1. Create an account and add `cm.com.br` as a sending domain.
2. Publish the DNS records shown in the provider dashboard and wait for verified
   status. Do not replace existing root MX/SPF records or enable receiving as
   part of this setup. DNS names/values must come from that account.
3. Create a sending-only API key scoped to this domain.
4. Configure `.env.production` on the VPS, never in Git or chat:

   ```dotenv
   SMTP_ADDRESS=smtp.resend.com
   SMTP_PORT=465
   SMTP_USERNAME=resend
   SMTP_PASSWORD=<sending-only-api-key>
   ```

5. Recreate `web` and `editorial_worker` to load the environment.
6. Save recipients in the admin screen, send a preview to your own admin email,
   check the PDF and provider status, then enable the schedule.

No actual receiving mailbox is created by this feature. If replies are needed,
set up a mailbox with an email hosting provider separately. The message currently
tells recipients not to reply. Keep open/click email tracking disabled unless
explicitly required; this integration does not enable it.

Official docs: https://resend.com/docs/send-with-smtp and
https://resend.com/docs/dashboard/domains/introduction

## Timing and delivery

The existing editorial worker checks every 30 minutes (configurable using
`EDITORIAL_INTERVAL_SECONDS`). Monday 08:00 America/Sao_Paulo is the default;
the admin can change the hour. Delivery is due at or after that hour, on the
next worker cycle, not guaranteed at exactly 08:00. A restart later that week
will catch up only the latest due week; there is no historical mass backfill.

The PDF uses the preceding Monday 00:00 UTC through next Monday 00:00 UTC,
matching the dashboard's existing complete-day convention. The mail labels UTC
explicitly; sending time is Brasília. No raw reader identifiers are exported.

Each recipient gets a separate message. Unique schedule/week/recipient keys
and row-locked claims prevent normal duplicate sends. The SMTP acceptance is
logged separately from inbox delivery. Provider rejections with temporary SMTP
codes retry at most three times, at least 30 minutes apart. PDF failures also
retry. Permanent rejections stop. Network failures after transport starts and
crashed `sending` records require checking the provider; they are not blindly
resent. Resend additionally receives a stable `Resend-Idempotency-Key` header.

Paused schedules, removed recipients and stale queued weeks are not sent.
An explicitly requested preview can run while paused, only to the requesting
admin's address, with a 30-minute cooldown per publication. Preview generation
and delivery run on the worker, not in the HTTP request.

Migration: `20261028180000_create_analytics_email_reports.rb` adds only the two
email scheduling tables. Deploy with a database backup and normal Docker image
rebuild. Test only on an isolated VPS database with ActionMailer test delivery;
never use live recipients for automated verification.
