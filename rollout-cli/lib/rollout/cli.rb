# frozen_string_literal: true

require 'optparse'
require 'time'
require 'date'
require_relative 'cli/version'

class Rollout
  module CLI
    class Error < StandardError
      attr_reader :status

      def initialize(status, message)
        @status = status
        super(message)
      end
    end

    def self.run(argv, out: $stdout, err: $stderr, env: ENV, now: Time.now)
      Command.new(out, err, env, now).run(argv)
    end
  end
end

require_relative 'cli/config'
require_relative 'cli/client'
require_relative 'cli/response'

class Rollout
  module CLI
    class Command
      def initialize(out, err, env, now)
        @out, @err, @env, @now = out, err, env, now
      end

      def run(argv)
        options = { limit: 100, config: File.join(@env.fetch('HOME', Dir.home), '.config/rollout/config.json') }
        parser = option_parser(options)
        args = parser.parse(argv.dup)
        if options[:help] || args == ['help']
          @out.puts(parser)
          return 0
        end
        if options[:version]
          @out.puts(VERSION)
          return 0
        end
        command, feature = args
        valid = case command
        when 'features' then args.size == 1
        when 'show' then args.size == 2
        when 'history' then (1..2).cover?(args.size)
        else false
        end
        raise Error.new(2, 'Expected features, show FEATURE, or history [FEATURE]; see --help') unless valid
        raise Error.new(2, 'An explicit --profile is required') if options[:profile].to_s.empty?
        raise Error.new(2, '--limit must be between 1 and 1000') unless (1..1000).cover?(options[:limit])
        raise Error.new(2, '--since is only valid for history') if options[:since] && command != 'history'
        raise Error.new(2, '--limit is not valid for show') if options[:limit_set] && command == 'show'
        if feature && (feature.empty? || feature.bytesize > 256 || feature.match?(/[[:cntrl:]]/))
          raise Error.new(2, 'FEATURE must contain 1 to 256 bytes without control characters')
        end
        since = parse_since(options[:since]) if options[:since]
        config = Config.new(options[:config], options[:profile], @env)
        path = feature ? "/features/#{escape_segment(feature)}" : '/features'
        path = feature ? "#{path}/history" : '/history' if command == 'history'
        query = command == 'show' ? {} : { limit: options[:limit] }
        query[:since] = since if since
        response = Client.new(config).get(path, query)
        Response.validate!(response, command: command, feature: feature, limit: options[:limit], since: since, environment: config.environment)
        if options[:json]
          @out.puts(JSON.generate(response))
        else
          render(response, command)
        end
        0
      rescue OptionParser::ParseError
        @err.puts('rollout: invalid option or argument; see --help')
        2
      rescue Error => e
        @err.puts("rollout: #{e.message}")
        e.status
      rescue Errno::EPIPE
        0
      end

      private

      def option_parser(options)
        OptionParser.new do |parser|
          parser.banner = <<~HELP
            Usage: rollout COMMAND [OPTIONS]

              features           List stored flags (sorted by name)
              show FEATURE       Inspect stored targeting state, not user evaluation
              history [FEATURE]  Read newest retained changes, global if FEATURE omitted

            Examples:
              rollout features --profile production --json
              rollout show chat --profile production --json
              rollout history chat --since 2026-09-01 --profile production --json
              rollout history --since 24h --profile production --json

            No default profile. Tokens come from the selected profile's environment
            variable or private file, never command arguments. History is retained
            data, not a complete audit log. JSON goes to stdout; errors to stderr.
          HELP
          parser.on('--profile NAME', 'Required configuration profile') { |value| options[:profile] = value }
          parser.on('--config PATH', 'Config JSON (default: ~/.config/rollout/config.json)') { |value| options[:config] = value }
          parser.on('--json', 'Emit the API v1 JSON envelope') { options[:json] = true }
          parser.on('--limit N', Integer, 'Maximum features/events: 1..1000 (default: 100)') do |value|
            options[:limit] = value
            options[:limit_set] = true
          end
          parser.on('--since TIME', 'History: inclusive UTC date, RFC3339, or duration (24h, 7d, 30m, 60s)') { |value| options[:since] = value }
          parser.on('-h', '--help', 'Show help') { options[:help] = true }
          parser.on('--version', 'Show CLI version') { options[:version] = true }
          parser.separator 'Exit codes: 0 success, 2 usage/config, 3 auth, 4 not found, 5 API/protocol, 6 transport.'
        end
      end

      def parse_since(value)
        time = if (match = /\A([1-9][0-9]{0,8})([smhd])\z/.match(value))
          @now - match[1].to_i * { 's' => 1, 'm' => 60, 'h' => 3600, 'd' => 86_400 }.fetch(match[2])
        elsif value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          Date.iso8601(value)
          Time.iso8601("#{value}T00:00:00Z")
        elsif Response.timestamp?(value)
          Time.iso8601(value)
        else
          raise ArgumentError
        end
        normalized = time.utc.iso8601(6)
        raise ArgumentError unless Response.timestamp?(normalized)
        normalized
      rescue ArgumentError, RangeError
        raise Error.new(2, 'Invalid --since; use a UTC date, RFC3339 timestamp with timezone, or positive duration such as 24h')
      end

      def escape_segment(value)
        value.b.bytes.map do |byte|
          character = byte.chr
          character.match?(/[A-Za-z0-9_~-]/) ? character : format('%%%02X', byte)
        end.join
      end

      def render(response, command)
        @out.puts("Environment: #{JSON.generate(response['environment'])}")
        case command
        when 'features'
          response['features'].each do |feature|
            @out.puts("#{JSON.generate(feature['name'])}  #{feature['percentage']}%  groups=#{JSON.generate(feature['groups'])}  users=#{feature['users'].length}")
          end
          @out.puts('No stored features returned.') if response['features'].empty?
        when 'show'
          @out.puts(JSON.pretty_generate(response['feature']))
        when 'history'
          response['events'].each { |event| @out.puts(JSON.pretty_generate(event)) }
          @out.puts('No retained events match this query.') if response['events'].empty?
          retention = response['meta']['retention']
          @out.puts("History enabled: #{retention['enabled']}; retention cap: #{retention['max_events'] || 'unknown'} events; oldest retained: #{JSON.generate(retention['oldest_available_at'])}.")
          @out.puts('Completeness is unknown: retention is count-based; deletion events are not recorded and feature deletion clears feature history.')
        end
        if response.dig('meta', 'truncated')
          @out.puts('Result limit reached; additional matching retained records exist. Increase --limit (maximum 1000).')
        end
      end
    end
  end
end
