# frozen_string_literal: true

require 'yaml'

class Rollout
  class InvalidDefinition < ArgumentError
  end

  class Definition
    attr_reader :name, :path, :description, :attributes

    def self.load(path)
      attributes = YAML.safe_load(File.read(path))
      raise InvalidDefinition, "#{path}: definition must be a mapping" unless attributes.is_a?(Hash)

      new(name: File.basename(path, '.yml'), attributes: attributes, path: path)
    rescue Psych::Exception => e
      raise InvalidDefinition, "#{path}: #{e.message}"
    end

    def initialize(name:, attributes: {}, path: nil)
      @name = name.to_sym
      @path = path
      @attributes = attributes.freeze
      @description = attributes['description']
      return if @description.nil? || @description.is_a?(String)

      raise InvalidDefinition, "#{path || name}: description must be a string"
    end
  end
end
