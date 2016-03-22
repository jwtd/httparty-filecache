require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end

require 'test/unit'
require 'mocha'
require 'shoulda'
require 'vcr'
require 'active_support/testing/assertions'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'httparty-filecache'
require 'twitter_api'

VCR.config do |c|
  c.cassette_library_dir = 'test/fixtures/vcr_cassettes'
  c.stub_with :webmock
  c.default_cassette_options = { :record => :none }
  c.allow_http_connections_when_no_cassette = false
end

HTTParty::HTTPCache.perform_caching = true

class Test::Unit::TestCase
  include ActiveSupport::Testing::Assertions

  def turn_off_caching
    HTTParty::HTTPCache.perform_caching = false
  end

  def turn_on_caching
    HTTParty::HTTPCache.perform_caching = true
  end

  def fixture_file(name)
    File.read(File.join(File.dirname(__FILE__), 'fixtures', name))
  end

  def mock_response_in_backup(hash)
    @cache.stubs(:exists).with("api-cache:twitter:#{hash}").returns(false)
    @cache.stubs(:exists).with("api-cache:twitter").returns(true)
    @cache.stubs(:hexists).with("api-cache:twitter", hash).returns(true)
    @cache.expects(:hget).with('api-cache:twitter', hash).returns(@response)
    @cache.expects(:set).with("api-cache:twitter:#{hash}", @response).returns(true)
    @cache.expects(:expire).with("api-cache:twitter:#{hash}", 300).returns(true)
  end

  def mock_no_response_in_backup(hash)
    @cache.stubs(:exists).with("api-cache:twitter:#{hash}").returns(false)
    @cache.stubs(:exists).with("api-cache:twitter").returns(true)
    @cache.stubs(:hexists).with("api-cache:twitter", hash).returns(false)
  end

  def mock_bad_response_from_server
    http_response = mock
    http_response.expects(:is_a?).with(Net::HTTPSuccess).returns(false)
    HTTParty::Response.any_instance.expects(:response).at_least_once.returns(http_response)
  end

  def mock_http_exception
    HTTParty::Request.any_instance.expects(:perform_without_caching).raises(Net::HTTPError.new("ERROR MESSAGE", stub('response')))
  end
end
