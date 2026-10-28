require "ipaddr"
require "digest"
require "net/http"
require "resolv"
require "timeout"
require "uri"
require "vips"

module Analytics
  class PdfImages
    CACHE = ActiveSupport::Cache::MemoryStore.new(size: 24.megabytes)
    MAX_BYTES = 3_000_000
    BLOCKED = %w[0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/3 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8].map { |range| IPAddr.new(range) }.freeze

    def initialize
      @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
    end

    def call(url)
      return unless allowed?(url)
      key = "pdf-image-v1:#{Digest::SHA256.hexdigest(url)}"
      cached = CACHE.read(key)
      return cached.presence if cached
      remaining = @deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if remaining <= 0

      bytes = Timeout.timeout([remaining, 4].min) { download(url) }
      result = compress(bytes)
      CACHE.write(key, result, expires_in: 1.hour)
      result
    rescue StandardError
      CACHE.write(key, "", expires_in: 1.minute) if key
      nil
    end

    def allowed?(value)
      uri = URI.parse(value.to_s)
      uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil? &&
        %w[correiodamanha.com.br www.correiodamanha.com.br].include?(uri.host)
    rescue URI::InvalidURIError
      false
    end

    private

    def download(url, redirects = 0)
      raise "Invalid image location" unless allowed?(url) && redirects <= 2
      uri = URI.parse(url)
      addresses = Resolv.getaddresses(uri.host)
      raise "Invalid image address" if addresses.empty? || addresses.any? do |address|
        ip = IPAddr.new(address).native
        BLOCKED.any? { |range| range.include?(ip) }
      end
      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.ipaddr = addresses.first
      http.use_ssl = true
      http.open_timeout = 2
      http.read_timeout = 2
      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = "CorreioContentHub/1.0 (audience report)"
      request["Accept"] = "image/jpeg,image/png,image/webp"
      bytes = +"".b
      redirect = nil
      http.start do
        http.request(request) do |response|
          if response.is_a?(Net::HTTPRedirection)
            redirect = URI.join(url, response.fetch("location")).to_s
            next
          end
          raise "Invalid image response" unless response.is_a?(Net::HTTPSuccess)
          raise "Image too large" if response["content-length"].to_i > MAX_BYTES
          response.read_body do |chunk|
            bytes << chunk
            raise "Image too large" if bytes.bytesize > MAX_BYTES
          end
        end
      end
      redirect ? download(redirect, redirects + 1) : bytes
    end

    def compress(bytes)
      # Raster signatures exclude SVGs, documents and loaders with external resources.
      raster = bytes.start_with?("\xFF\xD8".b, "\x89PNG\r\n\x1A\n".b) ||
        (bytes.start_with?("RIFF") && bytes.byteslice(8, 4) == "WEBP")
      raise "Unsupported image" unless raster
      original = Vips::Image.new_from_buffer(bytes, "", access: :sequential)
      raise "Image dimensions too large" if original.width * original.height > 24_000_000
      image = Vips::Image.thumbnail_buffer(bytes, 320, height: 240, size: :down).colourspace(:srgb)
      image = image.flatten(background: [255, 255, 255]) if image.has_alpha?
      image.jpegsave_buffer(Q: 78, strip: true)
    end
  end
end
