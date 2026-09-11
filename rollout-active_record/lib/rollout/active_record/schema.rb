# frozen_string_literal: true

class Rollout
  module ActiveRecord
    module Schema
      def self.create(connection, features_table: "rollout_features", events_table: "rollout_events")
        connection.create_table(features_table) do |table|
          table.string :name, null: false
          table.float :percentage, null: false, default: 0.0
          table.text :users, null: false
          table.text :groups, null: false
          table.text :data, null: false
          table.timestamps
        end
        connection.add_index(features_table, :name, unique: true)

        connection.create_table(events_table) do |table|
          table.string :feature_name, null: false
          table.string :event_name, null: false
          table.text :data, null: false
          table.text :context, null: false
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
      end

      def self.drop(connection, features_table: "rollout_features", events_table: "rollout_events")
        connection.drop_table(events_table, if_exists: true)
        connection.drop_table(features_table, if_exists: true)
      end
    end
  end
end
