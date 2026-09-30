# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'stringio'
require 'socket'
require 'open3'
require 'rbconfig'
require_relative '../lib/rollout/cli'

class CLITest < Minitest::Test
  TOKEN = 'test-secret-that-must-not-be-logged'
  NOW = Time.utc(2026, 9, 30, 12)

  def setup
    @directory = Dir.mktmpdir
    @path = File.join(@directory, 'config.json')
    @settings = { 'url' => 'https://example.invalid/api/rollout/v1', 'environment' => 'production', 'token_env' => 'TEST_TOKEN' }
    @env = { 'TEST_TOKEN' => TOKEN, 'HOME' => @directory }
    @out, @err = StringIO.new, StringIO.new
    write_config
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def write_config
    File.write(@path, JSON.generate('profiles' => { 'production' => @settings }), perm: 0o600)
  end

  def run_cli(*args)
    Rollout::CLI.run(args + ['--config', @path, '--profile', 'production'], out: @out, err: @err, env: @env, now: NOW)
  end

  def feature(name = 'chat')
    { 'name' => name, 'percentage' => 25.5, 'groups' => ['staff'], 'users' => ['123'], 'data' => { 'description' => 'Chat' } }
  end

  def envelope(fields)
    { 'api_version' => 1, 'environment' => 'production' }.merge(fields)
  end

  def features
    envelope('features' => [feature], 'meta' => { 'limit' => 100, 'truncated' => false })
  end

  def history(name = nil, since: nil)
    envelope(
      'events' => [{ 'feature' => name || 'chat', 'name' => 'update', 'data' => { 'before' => { 'percentage' => 0 }, 'after' => { 'percentage' => 25.5 } }, 'context' => { 'actor' => 'employee' }, 'created_at' => '2026-09-30T11:00:00.000000Z' }],
      'meta' => { 'limit' => 100, 'truncated' => false, 'scope' => name ? 'feature' : 'global', 'feature' => name, 'since' => since,
                  'retention' => { 'enabled' => true, 'max_events' => 100, 'oldest_available_at' => '2026-09-29T00:00:00Z', 'completeness' => 'unknown', 'deletion_events' => false } }
    )
  end

  # A real socket exercises Net::HTTP, request encoding, and executable IO together.
  def with_server(body, status: 200, content_type: 'application/json', extra_headers: '', delay: 0)
    server = TCPServer.new('127.0.0.1', 0)
    @settings['url'] = "http://127.0.0.1:#{server.addr[1]}/api/rollout/v1/"
    @settings['allow_http'] = true
    write_config
    payload = body.is_a?(String) ? body : JSON.generate(body)
    worker = Thread.new do
      client = server.accept
      request = +''
      request << client.gets until request.end_with?("\r\n\r\n")
      @request = request
      sleep(delay) if delay.positive?
      client.write("HTTP/1.1 #{status} Test\r\nContent-Type: #{content_type}\r\nContent-Length: #{payload.bytesize}\r\nConnection: close\r\n#{extra_headers}\r\n")
      client.write(payload)
    rescue Errno::EPIPE, Errno::ECONNRESET
      nil
    ensure
      client&.close
    end
    yield
    assert worker.join(5), 'HTTP test server did not finish'
    worker.value
  ensure
    worker&.kill
    server&.close
  end

  def assert_failure(status)
    assert_equal status, yield
    assert_empty @out.string
    refute_empty @err.string
    refute_includes @err.string, TOKEN
  end

  def test_help_and_version_need_no_config
    ['--help', 'help', 'history --help', '--version'].each do |args|
      output = StringIO.new
      assert_equal 0, Rollout::CLI.run(args.split, out: output, err: @err, env: {})
      refute_empty output.string
    end
  end

  def test_profile_is_always_explicit
    assert_failure(2) { Rollout::CLI.run(['features', '--config', @path], out: @out, err: @err, env: @env) }
  end

  def test_bad_usage_never_echoes_arguments
    [%w[delete chat], %w[show], %w[features extra], ['--token', TOKEN], %w[history --limit 0], %w[features --limit 1001], %w[features --limit NaN], %w[show chat --limit 1], %w[features --since 24h], ['show', '']].each do |args|
      assert_failure(2) { run_cli(*args) }
    end
  end

  def test_invalid_since
    ['yesterday', '0h', '-2d', '999999999d', '2026-02-30', '2026-09-01T12:00:00', '2026-09-01T99:00:00Z'].each do |value|
      assert_failure(2) { run_cli('history', '--since', value) }
    end
  end

  def test_features_json_over_http
    with_server(features) do
      assert_equal 0, run_cli('features', '--json')
      assert_equal features, JSON.parse(@out.string)
      assert_empty @err.string
    end
    assert_includes @request, 'GET /api/rollout/v1/features?limit=100 HTTP/1.1'
    assert_includes @request, "Authorization: Bearer #{TOKEN}"
    assert_includes @request, 'Accept: application/json'
    refute_includes @request, 'Cookie:'
  end

  def test_show_encodes_feature_as_one_path_segment
    name = 'a/b ?#%..é'
    with_server(envelope('feature' => feature(name))) { assert_equal 0, run_cli('show', name, '--json') }
    assert_includes @request, '/features/a%2Fb%20%3F%23%25%2E%2E%C3%A9 HTTP/1.1'
  end

  def test_global_relative_history
    since = '2026-09-29T12:00:00.000000Z'
    with_server(history(nil, since: since)) { assert_equal 0, run_cli('history', '--since', '24h', '--json') }
    assert_includes @request, '/history?limit=100&since=2026-09-29T12%3A00%3A00.000000Z'
    assert_equal since, JSON.parse(@out.string).dig('meta', 'since')
  end

  def test_feature_history_date_and_timestamp_filters
    { '2026-09-01' => '2026-09-01T00:00:00.000000Z', '2026-09-01T03:00:00+02:00' => '2026-09-01T01:00:00.000000Z', '30m' => '2026-09-30T11:30:00.000000Z' }.each do |input, expected|
      body = history('chat', since: expected)
      body['events'] = []
      with_server(body) { assert_equal 0, run_cli('history', 'chat', '--since', input, '--json') }
      assert_includes @request, '/features/chat/history?'
      assert_includes @request, URI.encode_www_form_component(expected)
    end
  end

  def test_readable_output_and_truncation
    body = features
    body['meta']['truncated'] = true
    with_server(body) { assert_equal 0, run_cli('features') }
    assert_includes @out.string, '25.5%'
    assert_includes @out.string, 'users=1'
    assert_includes @out.string, 'Result limit reached'
  end

  def test_history_discloses_retention_and_change_details
    with_server(history('chat')) { assert_equal 0, run_cli('history', 'chat') }
    %w[before after actor employee unknown deletion].each { |word| assert_includes @out.string, word }
  end

  def test_disabled_history_is_not_reported_as_complete
    body = history
    body['events'] = []
    body['meta']['retention']['enabled'] = false
    with_server(body) { assert_equal 0, run_cli('history') }
    assert_includes @out.string, 'History enabled: false'
    assert_includes @out.string, 'Completeness is unknown'
  end

  def test_custom_limit
    body = features
    body['meta']['limit'] = 1
    with_server(body) { assert_equal 0, run_cli('features', '--limit', '1', '--json') }
    assert_includes @request, '?limit=1 '
  end

  def test_http_errors_do_not_echo_bodies_or_follow_redirects
    { 301 => 5, 302 => 5, 401 => 3, 403 => 3, 404 => 4, 429 => 5, 500 => 5, 204 => 5 }.each do |http, exit_status|
      with_server(TOKEN, status: http, extra_headers: "Location: https://example.invalid/#{TOKEN}\r\n") do
        assert_failure(exit_status) { run_cli('features', '--json') }
      end
    end
  end

  def test_invalid_json_and_html
    with_server('{broken') { assert_failure(5) { run_cli('features', '--json') } }
    with_server(TOKEN, content_type: 'text/html') { assert_failure(5) { run_cli('features', '--json') } }
  end

  def test_response_byte_bound
    with_server(' ' * (Rollout::CLI::Client::MAX_BYTES + 1)) { assert_failure(5) { run_cli('features', '--json') } }
  end

  def test_unexpected_compression
    with_server(features, extra_headers: "Content-Encoding: gzip\r\n") { assert_failure(5) { run_cli('features') } }
  end

  def test_schema_environment_version_and_count_checks
    bodies = [[], {}, features.merge('api_version' => 2), features.merge('environment' => 'staging'), features.merge('features' => [{}]), features.merge('features' => [feature] * 101), features.merge('meta' => {})]
    bodies.each do |body|
      with_server(body) { assert_failure(5) { run_cli('features', '--json') } }
    end
  end

  def test_wrong_feature_response
    with_server(envelope('feature' => feature('other'))) { assert_failure(5) { run_cli('show', 'chat', '--json') } }
  end

  def test_history_cannot_claim_completeness_or_ignore_since
    body = history
    body['meta']['retention']['completeness'] = 'complete'
    with_server(body) { assert_failure(5) { run_cli('history', '--json') } }
    body = history(nil, since: '2026-09-30T12:00:00.000000Z')
    with_server(body) { assert_failure(5) { run_cli('history', '--since', '2026-09-30T12:00:00Z', '--json') } }
  end

  def test_config_requires_secure_url
    ['http://example.com/v1', 'https://user:password@example.com', 'https://example.com/?token=bad', 'https://example.com/#bad', 'file:///tmp/api', 'http://127.0.0.1/v1'].each do |url|
      @settings['url'] = url
      write_config
      assert_failure(2) { run_cli('features') }
    end
  end

  def test_unknown_profile_and_malformed_config
    assert_failure(2) { Rollout::CLI.run(['features', '--config', @path, '--profile', 'missing'], out: @out, err: @err, env: @env) }
    File.write(@path, '{}')
    assert_failure(2) { run_cli('features') }
    File.write(@path, '{invalid')
    assert_failure(2) { run_cli('features') }
    File.write(@path, '')
    assert_failure(2) { run_cli('features') }
  end

  def test_insecure_config_permissions
    File.chmod(0o666, @path)
    assert_failure(2) { run_cli('features') }
  end

  def test_tokens_must_be_present_and_header_safe
    ['', "#{TOKEN}\nInjected: yes"].each do |token|
      @env['TEST_TOKEN'] = token
      assert_failure(2) { run_cli('features') }
    end
  end

  def test_inline_and_ambiguous_tokens_rejected
    @settings['token'] = TOKEN
    write_config
    assert_failure(2) { run_cli('features') }
    @settings.delete('token')
    @settings['token_file'] = 'token'
    write_config
    assert_failure(2) { run_cli('features') }
  end

  def test_empty_private_token_file
    @settings.delete('token_env')
    @settings['token_file'] = 'token'
    File.write(File.join(@directory, 'token'), '', perm: 0o600)
    write_config
    assert_failure(2) { run_cli('features') }
  end

  def test_missing_config_file
    File.unlink(@path)
    assert_failure(2) { run_cli('features') }
  end

  def test_state_output_escapes_terminal_control_characters
    state = feature
    state['data']['description'] = "\e[31mred"
    with_server(envelope('feature' => state)) { assert_equal 0, run_cli('show', 'chat') }
    refute_includes @out.string, "\e"
    assert_includes @out.string, '\\u001b'
    assert_includes @out.string, '123'
  end

  def test_private_token_file_relative_to_config
    @settings.delete('token_env')
    @settings['token_file'] = 'token'
    token_path = File.join(@directory, 'token')
    File.write(token_path, "#{TOKEN}\n", perm: 0o600)
    with_server(features) { assert_equal 0, run_cli('features') }
    @out.truncate(0)
    @out.rewind
    File.chmod(0o644, token_path)
    assert_failure(2) { run_cli('features') }
  end

  def test_network_failure
    server = TCPServer.new('127.0.0.1', 0)
    @settings['url'] = "http://127.0.0.1:#{server.addr[1]}"
    @settings['allow_http'] = true
    server.close
    write_config
    assert_failure(6) { run_cli('features', '--json') }
  end

  def test_total_deadline
    timeout = Timeout.method(:timeout)
    short_deadline = lambda do |seconds, *arguments, &block|
      timeout.call(seconds == 30 ? 0.05 : seconds, *arguments, &block)
    end
    with_server(features, delay: 0.15) do
      Timeout.stub(:timeout, short_deadline) do
        assert_failure(6) { run_cli('features', '--json') }
      end
    end
  end

  def test_untrusted_tls_certificate_is_rejected
    key = OpenSSL::PKey::RSA.new(2048)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 1
    certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse('/CN=localhost')
    certificate.public_key = key.public_key
    certificate.not_before = Time.now - 60
    certificate.not_after = Time.now + 60
    certificate.sign(key, OpenSSL::Digest.new('SHA256'))
    context = OpenSSL::SSL::SSLContext.new
    context.cert, context.key = certificate, key
    tcp = TCPServer.new('127.0.0.1', 0)
    ssl = OpenSSL::SSL::SSLServer.new(tcp, context)
    @settings['url'] = "https://127.0.0.1:#{tcp.addr[1]}/api/v1"
    write_config
    worker = Thread.new do
      ssl.accept.close
    rescue OpenSSL::SSL::SSLError
      nil
    end
    assert_failure(6) { run_cli('features', '--json') }
    assert worker.join(5)
    worker.value
  ensure
    worker&.kill
    tcp&.close
  end

  def test_actual_executable_exit_and_streams
    with_server(features) do
      stdout, stderr, status = Open3.capture3(@env, RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), File.expand_path('../bin/rollout', __dir__), 'features', '--profile', 'production', '--config', @path, '--json')
      assert status.success?
      assert_equal features, JSON.parse(stdout)
      assert_empty stderr
    end
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), File.expand_path('../bin/rollout', __dir__), 'features')
    assert_equal 2, status.exitstatus
    assert_empty stdout
    assert_includes stderr, '--profile'
  end
end
