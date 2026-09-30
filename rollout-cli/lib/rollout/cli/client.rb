# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'timeout'

class Rollout
  module CLI
    class Client
      MAX_BYTES = 1_048_576

      def initialize(config)
        @config = config
      end

      def get(path, query)
        uri = @config.url.dup
        uri.path = uri.path.sub(%r{/+\z}, '') + path
        uri.query = URI.encode_www_form(query) unless query.empty?
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{@config.token}"
        request['Accept'] = 'application/json'
        request['Accept-Encoding'] = 'identity'
        request['User-Agent'] = "rollout-cli/#{VERSION}"
        http = Net::HTTP.new(uri.hostname, uri.port, nil)
        http.use_ssl = uri.scheme == 'https'
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = 5
        http.read_timeout = 10
        http.write_timeout = 10
        http.max_retries = 0
        body = +''
        Timeout.timeout(30) do
          http.start do
            http.request(request) do |response|
              check_status(response.code.to_i)
              unless response.content_type == 'application/json' && [nil, 'identity'].include?(response['Content-Encoding'])
                raise Error.new(5, 'Expected an uncompressed application/json response')
              end
              response.read_body do |chunk|
                raise Error.new(5, 'Response exceeds 1 MiB; use a smaller limit') if body.bytesize + chunk.bytesize > MAX_BYTES
                body << chunk
              end
            end
          end
        end
        JSON.parse(body)
      rescue JSON::ParserError
        raise Error.new(5, 'API returned invalid JSON')
      rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
        raise Error.new(6, 'HTTP connection failed or timed out; check endpoint, network, and TLS configuration')
      rescue Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError
        raise Error.new(5, 'Invalid HTTP response')
      end

      private

      def check_status(status)
        return if status == 200
        code = case status
        when 401, 403 then 3
        when 404 then 4
        else 5
        end
        raise Error.new(code, "API returned HTTP #{status}; redirects are not followed")
      end
    end
  end
end
