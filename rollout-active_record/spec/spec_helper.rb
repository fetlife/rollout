# frozen_string_literal: true

require 'simplecov'

SimpleCov.start

require 'bundler/setup'
require 'active_record'
require 'rollout'
require 'rollout/active_record'

ADAPTER = ENV.fetch('ROLLOUT_AR_ADAPTER', 'sqlite3')

def connection_config
  case ADAPTER
  when 'sqlite3'
    { adapter: 'sqlite3', database: ':memory:' }
  when 'postgresql'
    {
      adapter: 'postgresql',
      host: ENV.fetch('POSTGRES_HOST', '127.0.0.1'),
      port: ENV.fetch('POSTGRES_PORT', '5432'),
      database: ENV.fetch('POSTGRES_DB', 'rollout_test'),
      username: ENV.fetch('POSTGRES_USER', 'postgres'),
      password: ENV.fetch('POSTGRES_PASSWORD', 'postgres'),
    }
  when 'mysql2'
    {
      adapter: 'mysql2',
      host: ENV.fetch('MYSQL_HOST', '127.0.0.1'),
      port: ENV.fetch('MYSQL_PORT', '3306'),
      database: ENV.fetch('MYSQL_DATABASE', 'rollout_test'),
      username: ENV.fetch('MYSQL_USER', 'root'),
      password: ENV.fetch('MYSQL_PASSWORD', ''),
      encoding: 'utf8mb4',
    }
  else
    raise "Unknown ROLLOUT_AR_ADAPTER=#{ADAPTER}"
  end
end

def create_rollout_schema(connection = ActiveRecord::Base.connection, **tables)
  Rollout::ActiveRecord::Schema.drop(connection, **tables)
  Rollout::ActiveRecord::Schema.create(connection, **tables)
end

def active_record_backend(**options)
  Rollout::ActiveRecord::Backend.new(**options)
end

ActiveRecord::Base.establish_connection(connection_config)
create_rollout_schema

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    ActiveRecord::Base.connection.execute("DELETE FROM rollout_events")
    ActiveRecord::Base.connection.execute("DELETE FROM rollout_features")
  end
end
