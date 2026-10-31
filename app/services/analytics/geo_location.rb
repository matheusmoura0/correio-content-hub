require "ipaddr"
require "maxmind/db"

module Analytics
  class GeoLocation
    ATTRIBUTION = "IP location estimated using DB-IP City Lite (CC BY 4.0): https://db-ip.com".freeze
    MUTEX = Mutex.new

    def self.path
      Rails.root.join("geoip", "dbip-city-lite.mmdb")
    end

    def self.call(address)
      ip = IPAddr.new(address.to_s).native
      return {} if ip.private? || ip.loopback? || ip.link_local? || !path.file?
      MUTEX.synchronize do
        stamp = [path.mtime.to_f, path.size]
        if @stamp != stamp
          replacement = MaxMind::DB.new(path.to_s)
          @reader&.close
          @reader, @stamp = replacement, stamp
        end
        data = @reader.get(ip.to_s) || {}
        country = data.dig("country", "iso_code")
        return {} unless country.to_s.match?(/\A[A-Z]{2}\z/) && !%w[XX ZZ].include?(country)
        { country_code: country, region: data.dig("subdivisions", 0, "names", "en")&.first(80),
          city: data.dig("city", "names", "en")&.first(80), geo_source: "dbip_city_lite" }.compact
      end
    rescue StandardError => error
      Rails.logger.debug("GeoIP unavailable: #{error.class}")
      {}
    end
  end
end
