# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/helm"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Helm::MetadataFinder do
  subject(:finder) { described_class.new(dependency: dependency, credentials: []) }

  let(:repository) { "https://open-telemetry.github.io/opentelemetry-helm-charts" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "opentelemetry-collector",
      version: "0.182.0",
      previous_version: "0.180.0",
      requirements: [{
        file: "Chart.yaml",
        requirement: nil,
        groups: [],
        source: { registry: repository, tag: "0.182.0" },
        metadata: { type: :helm_chart }
      }],
      package_manager: "helm"
    )
  end
  let(:index_yaml) do
    <<~YAML
      apiVersion: v1
      entries:
        opentelemetry-collector:
          - name: opentelemetry-collector
            version: 0.182.0
            home: https://opentelemetry.io/
            sources:
              - https://opentelemetry.io/docs/collector/
              - https://github.com/open-telemetry/opentelemetry-helm-charts
          - name: opentelemetry-collector
            version: 0.180.0
            sources:
              - https://github.com/open-telemetry/opentelemetry-helm-charts
    YAML
  end

  before do
    stub_request(:get, "#{repository}/index.yaml").to_return(status: 200, body: index_yaml)
  end

  it_behaves_like "a dependency metadata finder"

  it "is the metadata finder registered for helm" do
    expect(Dependabot::MetadataFinders.for_package_manager("helm")).to eq(described_class)
  end

  describe "#source_url" do
    context "with a chart from an HTTPS chart repository" do
      it "uses the first source URL that points to a code host" do
        expect(finder.source_url).to eq("https://github.com/open-telemetry/opentelemetry-helm-charts")
      end
    end

    context "when the repository URL has a trailing slash" do
      let(:repository) { "https://open-telemetry.github.io/opentelemetry-helm-charts/" }

      before do
        stub_request(:get, "https://open-telemetry.github.io/opentelemetry-helm-charts/index.yaml")
          .to_return(status: 200, body: index_yaml)
      end

      it "finds the source" do
        expect(finder.source_url).to eq("https://github.com/open-telemetry/opentelemetry-helm-charts")
      end
    end

    context "when the chart lists only a home URL" do
      let(:index_yaml) do
        <<~YAML
          entries:
            opentelemetry-collector:
              - version: 0.182.0
                home: https://github.com/open-telemetry/opentelemetry-helm-charts
        YAML
      end

      it "falls back to the home URL" do
        expect(finder.source_url).to eq("https://github.com/open-telemetry/opentelemetry-helm-charts")
      end
    end

    context "when the chart is not in the index" do
      let(:index_yaml) { "entries: {}\n" }

      it { expect(finder.source_url).to be_nil }
    end

    context "when the index can't be fetched" do
      before do
        stub_request(:get, "#{repository}/index.yaml").to_return(status: 404, body: "Not Found")
      end

      it { expect(finder.source_url).to be_nil }
    end

    context "with a docker image from values.yaml" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nginx",
          version: "1.27.0",
          requirements: [{
            file: "values.yaml",
            requirement: nil,
            groups: [],
            source: { registry: "registry-1.docker.io", tag: "1.27.0" }
          }],
          package_manager: "helm"
        )
      end

      it "looks the source up from the image labels" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("regctl image inspect registry-1.docker.io/nginx:1.27.0")
          .and_return({ config: { Labels: {
            "org.opencontainers.image.source" => "https://github.com/nginx/docker-nginx"
          } } }.to_json)

        expect(finder.source_url).to eq("https://github.com/nginx/docker-nginx")
      end
    end
  end
end
