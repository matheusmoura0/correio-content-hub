ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"
require "minitest/mock"

class AnalyticsPdfImagesTest < Minitest::Test
  def setup
    Analytics::PdfImages::CACHE.clear
    @images = Analytics::PdfImages.new
  end

  def test_only_official_https_images_and_public_pinned_addresses_are_allowed
    ["http://www.correiodamanha.com.br/photo.jpg", "https://evil.example/photo.jpg",
      "https://user@www.correiodamanha.com.br/photo.jpg", "https://www.correiodamanha.com.br:8443/photo.jpg",
      "file:///etc/passwd", "data:image/png;base64,AA=="].each { |url| assert_nil @images.call(url) }
    %w[127.0.0.1 169.254.169.254 ::1 ::ffff:127.0.0.1].each do |address|
      Resolv.stub(:getaddresses, [address]) do
        assert_raises(RuntimeError) { @images.send(:download, "https://www.correiodamanha.com.br/image.jpg") }
      end
    end
  end

  def test_supported_rasters_are_resized_compressed_and_cached
    source = Vips::Image.black(1000, 500).pngsave_buffer
    calls = 0
    @images.stub(:download, ->(*) { calls += 1; source }) do
      2.times do
        result = @images.call("https://www.correiodamanha.com.br/image.png")
        image = Vips::Image.new_from_buffer(result, "")
        assert_equal 320, image.width
        assert_equal 160, image.height
        assert result.start_with?("\xFF\xD8".b)
      end
    end
    assert_equal 1, calls
    webp = Vips::Image.black(20, 20).webpsave_buffer
    assert @images.send(:compress, webp).start_with?("\xFF\xD8".b)
  end

  def test_invalid_missing_or_timed_out_images_do_not_break_reports
    @images.stub(:download, ->(*) { "<svg>untrusted</svg>" }) do
      assert_nil @images.call("https://www.correiodamanha.com.br/invalid.svg")
    end
    @images.stub(:download, ->(*) { raise Timeout::Error }) do
      assert_nil @images.call("https://www.correiodamanha.com.br/slow.jpg")
    end
    @images.instance_variable_set(:@deadline, 0)
    @images.stub(:download, ->(*) { flunk "Must respect image fetch budget" }) do
      assert_nil @images.call("https://www.correiodamanha.com.br/uncached.jpg")
    end
  end
end
