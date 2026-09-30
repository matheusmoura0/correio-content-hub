Rails.application.config.session_store(
  :cookie_store,
  key: "_correio_content_hub_v2_session",
  secure: Rails.env.production? && ENV.fetch("FORCE_SSL", "true") != "false",
  httponly: true,
  same_site: :lax
)
