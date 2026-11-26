# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "dependabot/python/update_checker/pip_version_resolver"
require "dependabot/uv/name_normaliser"
require "dependabot/uv/requirement"
require "dependabot/uv/update_checker"
require "dependabot/uv/version"

module Dependabot
  module Uv
    class UpdateChecker
      # UV uses the same pip version resolution logic as Python.
      # Both ecosystems share LanguageVersionManager, LatestVersionFinder,
      # and PythonRequirementParser via aliases, so we reuse Python's implementation.
      class PipVersionResolver < Dependabot::Python::UpdateChecker::PipVersionResolver
        extend T::Sig

        LOWER_BOUND_OPERATORS = %w(>= ~> =).freeze

        private

        # uv locks for the whole `requires-python` range and rejects a release whose
        # minimum Python is above the project's lower bound
        # (https://docs.astral.sh/uv/reference/internals/resolver/#requires-python).
        # When that bound is older than the interpreter Dependabot runs, check
        # releases against the bound so `uv lock` doesn't fail on the older split.
        sig { override.returns(String) }
        def release_python_version
          installed = super
          lower_bound = requires_python_lower_bound
          return installed unless lower_bound && lower_bound < Uv::Version.new(installed)
          return installed if dependency_has_marker?

          lower_bound.to_s
        end

        sig { returns(T.nilable(Gem::Version)) }
        def requires_python_lower_bound
          requirement_string = project_table["requires-python"]
          return unless requirement_string.is_a?(String)

          requirement = Uv::Requirement.new(requirement_string)
          lower_bound = requirement.requirements.filter_map do |op, version|
            version if LOWER_BOUND_OPERATORS.include?(op)
          end.max
          lower_bound if lower_bound && requirement.satisfied_by?(lower_bound)
        rescue ArgumentError # includes Gem::Requirement::BadRequirementError
          nil
        end

        # A dependency limited by an environment marker (e.g. `python_version >= "3.9"`)
        # may need a newer Python than the project's lower bound, so keep the old check.
        sig { returns(T::Boolean) }
        def dependency_has_marker?
          dependency_name = NameNormaliser.normalise(dependency.name)
          root_pyproject_requirement_strings.any? do |entry|
            requirement, marker = marker_evaluator.split_requirement_and_marker(entry)
            next false if marker.nil? || requirement.nil?

            # PEP 508 name: the leading run of letters, digits, ".", "_" and "-".
            name = requirement[/\A[A-Za-z0-9][A-Za-z0-9._-]*/]
            !name.nil? && NameNormaliser.normalise(name) == dependency_name
          end
        end

        sig { returns(T::Array[String]) }
        def root_pyproject_requirement_strings
          optional = project_table["optional-dependencies"]
          groups = root_pyproject_data["dependency-groups"]
          lists = [project_table["dependencies"]]
          lists += optional.values if optional.is_a?(Hash)
          lists += groups.values if groups.is_a?(Hash)
          lists.flat_map { |list| list.is_a?(Array) ? list.grep(String) : [] }
        end

        sig { returns(T::Hash[String, Object]) }
        def project_table
          project = root_pyproject_data["project"]
          project.is_a?(Hash) ? project : {}
        end

        sig { returns(T::Hash[String, Object]) }
        def root_pyproject_data
          @root_pyproject_data ||= T.let(
            begin
              pyproject = dependency_files.find { |file| file.name == "pyproject.toml" }
              pyproject&.content ? TomlRB.parse(pyproject.content) : {}
            rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
              {}
            end,
            T.nilable(T::Hash[String, Object])
          )
        end
      end
    end
  end
end
