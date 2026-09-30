# frozen_string_literal: true

require 'json'
require 'uri'

class Rollout
  module CLI
    class Config
      attr_reader :url, :environment, :token

      def initialize(path, profile, env)
        document = JSON.parse(read_file(path, secret: false))
        settings = document.fetch('profiles').fetch(profile)
        raise Error.new(2, 'Invalid profile configuration') unless settings.is_a?(Hash)
        @environment = settings.fetch('environment')
        unless @environment.is_a?(String) && !@environment.empty?
          raise Error.new(2, 'Profile requires an environment')
        end
        @url = URI(settings.fetch('url'))
        loopback = ['localhost', '127.0.0.1', '[::1]'].include?(@url.host)
        secure = @url.is_a?(URI::HTTPS)
        local = @url.is_a?(URI::HTTP) && loopback && settings['allow_http'] == true
        unless (secure || local) && @url.host && !@url.userinfo && !@url.query && !@url.fragment
          raise Error.new(2, 'Profile URL must use HTTPS without credentials, query, or fragment (HTTP requires loopback and allow_http)')
        end
        if settings.key?('token') || settings.key?('token_env') == settings.key?('token_file')
          raise Error.new(2, 'Configure exactly one of token_env or token_file; inline tokens are forbidden')
        end
        @token = if settings.key?('token_env')
          key = settings['token_env']
          raise Error.new(2, 'Invalid token_env name') unless key.is_a?(String) && key.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
          env.fetch(key, '')
        else
          read_file(File.expand_path(settings.fetch('token_file'), File.dirname(File.expand_path(path))), secret: true).strip
        end
        unless @token.is_a?(String) && @token.match?(/\A[A-Za-z0-9._~+\/-]+=*\z/)
          raise Error.new(2, 'Missing or invalid bearer token')
        end
      rescue JSON::ParserError, KeyError, TypeError, ArgumentError
        raise Error.new(2, 'Invalid configuration or unknown profile')
      end

      private

      def read_file(path, secret:)
        File.open(File.expand_path(path), 'r') do |file|
          stat = file.stat
          mask = secret ? 0o077 : 0o022
          unless stat.file? && stat.uid == Process.uid && (stat.mode & mask).zero?
            raise Error.new(2, secret ? 'Token file must be owned by you with mode 0600 or 0400' : 'Config must be owned by you and not writable by group or others')
          end
          value = file.read(65_537) || ''
          raise Error.new(2, 'Configuration file exceeds 64 KiB') if value.bytesize > 65_536
          value
        end
      rescue SystemCallError, IOError
        raise Error.new(2, 'Cannot read configuration or token file')
      end
    end
  end
end
