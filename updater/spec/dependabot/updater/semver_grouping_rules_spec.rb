# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/updater/semver_grouping_rules"
require "dependabot/dependency"
require "dependabot/dependency_group"
require "dependabot/job"
require "dependabot/update_checkers/base"
require "dependabot/pre_commit"

RSpec.describe Dependabot::Updater::SemverGroupingRules do
  subject(:allow_grouping) do
    described_class.new(job: job).allow_grouping?(group, dependency, checker) { :own }
  end

  let(:job) { instance_double(Dependabot::Job, package_manager: "pre_commit") }
  let(:group) do
    Dependabot::DependencyGroup.new(
      name: "pre-commit-hooks",
      rules: { "patterns" => ["*"], "update-types" => update_types }
    )
  end
  let(:update_types) { %w(minor patch) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "https://github.com/astral-sh/ruff-pre-commit",
      version: current_version,
      requirements: [],
      package_manager: "pre_commit"
    )
  end
  let(:checker) do
    instance_double(
      Dependabot::UpdateCheckers::Base,
      latest_version: Dependabot::PreCommit::Version.new(latest_version)
    )
  end

  context "when the current version has no \"v\" prefix" do
    let(:current_version) { "0.13.5" }
    let(:latest_version) { "0.13.7" }

    it { is_expected.to be(true) }
  end

  context "when the current version has a \"v\" prefix" do
    let(:current_version) { "v0.17.2" }

    context "with a patch update the group allows" do
      let(:latest_version) { "0.17.4" }

      it { is_expected.to be(true) }
    end

    context "with a minor update the group allows" do
      let(:latest_version) { "0.18.0" }

      it { is_expected.to be(true) }
    end

    context "with a major update the group does not allow" do
      let(:latest_version) { "1.0.0" }

      it { is_expected.to be(false) }
    end

    context "with a minor update when the group only allows patch updates" do
      let(:update_types) { %w(patch) }
      let(:latest_version) { "0.18.0" }

      it { is_expected.to be(false) }
    end
  end

  context "when the current version is a commit SHA" do
    let(:current_version) { "c6755bbf1dd25f5e7f3b8cf7f8c0a0b2e3c1d4e5" }
    let(:latest_version) { "0.17.4" }

    it { is_expected.to be(false) }
  end
end
