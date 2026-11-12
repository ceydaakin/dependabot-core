# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/dependency_graphers/base"
require "dependabot/python/file_parser"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      # A poetry.lock can pin one package at several versions, each behind its own environment marker (e.g. a
      # different urllib3 per Python version range). The file parser merges those entries into one dependency,
      # so this expands a parsed dependency back into one dependency per locked version.
      class PoetryLockedVersions
        extend T::Sig

        # Same non-registry sources that PyprojectFilesParser#lockfile_dependencies skips.
        NON_REGISTRY_SOURCE_TYPES = %w(directory git url).freeze

        sig { params(poetry_lock: T.nilable(Dependabot::DependencyFile)).void }
        def initialize(poetry_lock)
          @versions_by_name = T.let(
            poetry_lock ? parse_versions_by_name(poetry_lock) : {},
            T::Hash[String, T::Array[String]]
          )
        end

        # Returns the dependency itself unless poetry.lock pins its package at more than one version.
        sig { params(dependency: Dependabot::Dependency).returns(T::Array[Dependabot::Dependency]) }
        def expand(dependency)
          versions = @versions_by_name.fetch(NameNormaliser.normalise(dependency.name), [])
          return [dependency] if versions.length < 2

          versions.map do |version|
            Dependabot::Dependency.new(
              name: dependency.name,
              version: version,
              requirements: [],
              package_manager: dependency.package_manager
            )
          end
        end

        private

        sig { params(poetry_lock: Dependabot::DependencyFile).returns(T::Hash[String, T::Array[String]]) }
        def parse_versions_by_name(poetry_lock)
          FileParser::PoetryLock.from_file(poetry_lock).packages
                                .reject { |package| NON_REGISTRY_SOURCE_TYPES.include?(package.source_type) }
                                .group_by { |package| NameNormaliser.normalise(package.name) }
                                .transform_values { |packages| packages.map(&:version).uniq }
        end
      end
    end
  end
end
