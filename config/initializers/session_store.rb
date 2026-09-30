Rails.application.config.session_store(
  :cookie_store,
  key: "_correio_content_hub_v2_session",
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax
)
