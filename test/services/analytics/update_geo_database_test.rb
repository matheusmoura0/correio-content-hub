ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "stringio"

class UpdateGeoDatabaseTest < Minitest::Test
  def test_binary_download_is_atomic_and_failures_preserve_existing_database
    bytes = ("\xFF\xFE\x00\x80".b * 100)
    buffer = StringIO.new("".b)
    writer = Zlib::GzipWriter.new(buffer)
    writer.write(bytes)
    writer.close
    compressed = buffer.string
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:read_body) { |&block| block.call(compressed) }
    http = Object.new
    http.define_singleton_method(:request) { |_, &block| block.call(response) }
    reader = Object.new
    reader.define_singleton_method(:get) { |_| { "country" => { "iso_code" => "US" } } }
    reader.define_singleton_method(:close) {}
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("geo.mmdb")
      Analytics::GeoLocation.stub(:path, path) do
        Net::HTTP.stub(:start, ->(*_, **_, &block) { block.call(http) }) do
          MaxMind::DB.stub(:new, reader) do
            assert Analytics::UpdateGeoDatabase.call(force: true)
            assert_equal bytes, File.binread(path)
            refute Analytics::UpdateGeoDatabase.call
          end
        end
        path.dirname.join("version").write("old")
        Net::HTTP.stub(:start, ->(*_, **_) { raise Timeout::Error }) do
          refute Analytics::UpdateGeoDatabase.call(force: true)
          assert_equal bytes, File.binread(path)
        end
        refute Dir.children(dir).any? { |name| name.start_with?("geoip") }
      end
    end
  end
end
