Rails.application.config.filter_parameters += [:password, :password_confirmation, :token]
Rails.application.config.filter_parameters += %i[session_id path referrer entry_referrer target_url target_text
  entry_path previous_path utm_source utm_medium utm_campaign client_occurred_at time_zone image_url author_image_url]
