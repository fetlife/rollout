# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Rollout
  module ActiveRecord
    class InstallGenerator < ::Rails::Generators::Base
      include ::ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :database, type: :string, desc: "Database key to generate the migration for"

      def self.next_migration_number(dirname)
        ::ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def copy_migration
        migration_template(
          "create_rollout_tables.rb.tt",
          File.join(db_migrate_path, "create_rollout_tables.rb"),
        )
      end
    end
  end
end
