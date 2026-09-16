# frozen_string_literal: true

class Rollout
  module ActiveRecord
    module Schema
      def self.create(connection, features_table: "rollout_features", events_table: "rollout_events")
        name_options = name_column_options(connection)
        payload_options = payload_column_options(connection)

        connection.create_table(features_table) do |table|
          table.string :name, **name_options
          table.float :percentage, limit: 53, null: false, default: 0.0
          table.text :users, **payload_options
          table.text :groups, **payload_options
          table.text :data, **payload_options
          table.timestamps
        end
        connection.add_index(features_table, :name, unique: true)

        connection.create_table(events_table) do |table|
          table.string :feature_name, **name_options
          table.string :event_name, null: false
          table.text :data, **payload_options
          table.text :context, **payload_options
          table.boolean :feature_visible, null: false, default: true
          table.boolean :global_visible, null: false, default: true
          table.datetime :occurred_at, null: false, precision: 6
        end
        connection.add_index(
          events_table,
          [:feature_name, :feature_visible, :occurred_at],
          name: "index_#{events_table}_for_feature_history",
        )
        connection.add_index(
          events_table,
          [:global_visible, :occurred_at],
          name: "index_#{events_table}_for_global_history",
        )
        connection.add_index(
          events_table,
          [:feature_visible, :global_visible],
          name: "index_#{events_table}_for_hidden_cleanup",
        )
      end

      def self.drop(connection, features_table: "rollout_features", events_table: "rollout_events")
        connection.drop_table(events_table, if_exists: true)
        connection.drop_table(features_table, if_exists: true)
      end

      def self.name_column_options(connection)
        options = { null: false }
        options[:collation] = "utf8mb4_bin" if connection.adapter_name.match?(/mysql/i)
        options
      end

      def self.payload_column_options(connection)
        options = { null: false }
        options[:limit] = 16_777_215 if connection.adapter_name.match?(/mysql/i)
        options
      end
    end
  end
end
