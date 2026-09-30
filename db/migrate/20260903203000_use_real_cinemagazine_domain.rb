class UseRealCinemagazineDomain < ActiveRecord::Migration[8.1]
  def up
    site = Site.find_by(publication_key: "cinemagazine") || Site.find_by(domain: "cinemagazine.com.br")
    return unless site

    site.update_columns(
      domain: "revistacinemagazine.com.br",
      allowed_origins: "https://revistacinemagazine.com.br\nhttps://www.revistacinemagazine.com.br",
      updated_at: Time.current
    )
  end

  def down
    site = Site.find_by(publication_key: "cinemagazine") || Site.find_by(domain: "revistacinemagazine.com.br")
    return unless site

    site.update_columns(
      domain: "cinemagazine.com.br",
      allowed_origins: "https://cinemagazine.com.br\nhttps://www.cinemagazine.com.br",
      updated_at: Time.current
    )
  end
end
