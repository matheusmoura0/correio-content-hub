require "net/http"
require "tempfile"
require "timeout"
require "zlib"

module Analytics
  class UpdateGeoDatabase
    def self.call(force: false)
      path = GeoLocation.path
      FileUtils.mkdir_p(path.dirname)
      File.open(path.dirname.join("update.lock"), "w") do |lock|
        return false unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        month = Time.now.utc.strftime("%Y-%m")
        version = path.dirname.join("version")
        return false if path.file? && version.file? && version.read.strip == month
        attempt = path.dirname.join("last_attempt")
        return false if !force && attempt.file? && attempt.mtime > 6.hours.ago
        FileUtils.touch(attempt)
        Tempfile.create(["geoip", ".gz"], path.dirname) do |compressed|
          compressed.binmode
          Timeout.timeout(180) do
            uri = URI("https://download.db-ip.com/free/dbip-city-lite-#{month}.mmdb.gz")
            size = 0
            Net::HTTP.start(uri.host, 443, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
              http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
                raise "GeoIP HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
                response.read_body do |chunk|
                  size += chunk.bytesize
                  raise "GeoIP download too large" if size > 100.megabytes
                  compressed.write(chunk)
                end
              end
            end
            compressed.flush
            Tempfile.create(["geoip", ".mmdb"], path.dirname) do |database|
              database.binmode
              expanded = 0
              Zlib::GzipReader.open(compressed.path) do |gzip|
                until gzip.eof?
                  chunk = gzip.read(64.kilobytes)
                  expanded += chunk.bytesize
                  raise "GeoIP database too large" if expanded > 500.megabytes
                  database.write(chunk)
                end
              end
              database.flush
              reader = MaxMind::DB.new(database.path)
              reader.get("8.8.8.8")
              reader.close
              File.chmod(0644, database.path)
              File.rename(database.path, path)
              version.write(month)
            end
          end
        end
        Rails.logger.info("GeoIP database refreshed: #{month}; #{GeoLocation::ATTRIBUTION}")
        true
      end
    rescue StandardError => error
      Rails.logger.warn("GeoIP update failed; existing database preserved: #{error.class}")
      false
    end
  end
end
