# typed: strict
# frozen_string_literal: true

require "uri"
require "yaml"
require "dependabot/docker/metadata_finder"
require "dependabot/metadata_finders"
require "dependabot/registry_client"
require "dependabot/source"
require "sorbet-runtime"

module Dependabot
  module Helm
    # Chart dependencies from an HTTP(S) chart repository have no OCI image to
    # inspect, so their source comes from the chart's `sources`/`home` fields in
    # the repository's index.yaml. Images (values.yaml) and OCI charts keep the
    # Docker lookup.
    class MetadataFinder < Dependabot::Docker::MetadataFinder
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        repository = chart_repository_url
        return super unless repository

        source_from_chart_index(repository)
      end

      sig { returns(T.nilable(String)) }
      def chart_repository_url
        registry = dependency.requirements.first&.source_string("registry")
        return unless registry

        scheme = URI.parse(registry).scheme
        registry if %w(http https).include?(scheme)
      rescue URI::InvalidURIError
        nil
      end

      sig { params(repository: String).returns(T.nilable(Dependabot::Source)) }
      def source_from_chart_index(repository)
        entry = chart_index_entry(repository)
        return unless entry

        candidate_urls(entry).each do |url|
          source = Dependabot::Source.from_url(url)
          return source if source
        end
        nil
      rescue StandardError => e
        Dependabot.logger.warn("Error looking up Helm chart source: #{e.message}")
        nil
      end

      sig { params(repository: String).returns(T.nilable(T::Hash[String, Object])) }
      def chart_index_entry(repository)
        response = Dependabot::RegistryClient.get(url: "#{repository.chomp('/')}/index.yaml")
        return unless response.status == 200

        index = YAML.safe_load(response.body, permitted_classes: [Date, Time])
        entries = index.is_a?(Hash) ? index.dig("entries", dependency.name) : nil
        return unless entries.is_a?(Array) && entries.any?

        hashes = entries.grep(Hash)
        hashes.find { |e| e["version"].to_s == dependency.version } || hashes.first
      end

      sig { params(entry: T::Hash[String, Object]).returns(T::Array[String]) }
      def candidate_urls(entry)
        sources = entry["sources"]
        [*(sources.is_a?(Array) ? sources : []), entry["home"]].grep(String)
      end
    end
  end
end

Dependabot::MetadataFinders.register("helm", Dependabot::Helm::MetadataFinder)
