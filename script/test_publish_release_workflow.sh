#!/usr/bin/env bash
set -euo pipefail

readonly root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly workflow_path="$root_dir/.github/workflows/publish-release.yml"

ruby - "$workflow_path" <<'RUBY'
require "yaml"

path = ARGV.fetch(0)
text = File.read(path)
workflow = YAML.safe_load(text, aliases: true)
triggers = workflow["on"] || workflow[true]
abort "workflow must be manual-only" unless triggers.is_a?(Hash) && triggers.keys == ["workflow_dispatch"]
abort "permissions must be actions read and contents write" unless workflow["permissions"] == {"actions" => "read", "contents" => "write"}
abort "publisher must not request an environment" if text.match?(/^\s*environment:/)
abort "publisher must not request secrets" if text.include?("secrets.")

inputs = triggers.fetch("workflow_dispatch").fetch("inputs")
abort "publisher inputs are incomplete" unless inputs.keys.sort == %w[build_number validation_run_id version]

jobs = workflow.fetch("jobs")
authorize = jobs.fetch("authorize")
publish = jobs.fetch("publish-draft")
abort "publisher must depend on authorization" unless publish["needs"] == "authorize"

authorize_run = authorize.fetch("steps").map { |step| step["run"].to_s }.join("\n")
%w[workflow_dispatch refs/heads/main RELEASE_REF_PROTECTED].each do |gate|
  abort "missing authorization gate #{gate}" unless authorize_run.include?(gate)
end
abort "canonical version validation is missing" unless authorize_run.include?("(0|[1-9][0-9]*)")
abort "build number validation is missing" unless authorize_run.include?("{0,2}")
abort "validation run ID validation is missing" unless authorize_run.include?("VALIDATION_RUN_ID")

steps = publish.fetch("steps")
checkout = steps.find { |step| step["uses"].to_s.start_with?("actions/checkout@") }
abort "pinned checkout is missing" unless checkout && checkout["uses"].match?(/\Aactions\/checkout@[0-9a-f]{40}\z/)
abort "checkout must target the dispatch SHA" unless checkout.dig("with", "ref") == "${{ github.sha }}"
abort "checkout must not persist credentials" unless checkout.dig("with", "persist-credentials") == false
uses = steps.map { |step| step["uses"] }.compact
abort "only GitHub checkout action is permitted" unless uses.all? { |entry| entry.match?(/\Aactions\/checkout@[0-9a-f]{40}\z/) }

publish_run = steps.fetch(1).fetch("run")
%w[
  mktemp
  trap
  script/render_release_notes.sh
  actions/runs/$VALIDATION_RUN_ID
  completed
  success
  workflow_dispatch
  display_title
  validation_repository
  validation_status
  validation_conclusion
  validation_event
  validation_workflow_path
  validation_title
  head_branch
  head_sha
  for\ architecture\ in\ arm64\ x86_64
  artifact_name="Bairometer-$RELEASE_VERSION-$architecture"
  unzip
  sha256sum
  matching-refs
  git/tags
  git/refs
  gh
  gh\ release\ edit
  gh\ release\ upload
  --clobber
  --draft
  --verify-tag
].each do |required|
  abort "publisher is missing #{required}" unless publish_run.include?(required)
end
abort "publisher must use a bilingual notes renderer" unless publish_run.include?("render_release_notes.sh \"$tag\"")
abort "publisher must append checksums" unless publish_run.include?("## Checksums")
abort "publisher must bind the run to this repository" unless publish_run.include?("validation_repository\" == \"$GH_REPO")
abort "publisher must bind the run to the requested source SHA" unless publish_run.include?("validation_sha\" == \"$RELEASE_SHA")
abort "publisher must bind the run to the requested version and build" unless publish_run.include?("Protected release validation $RELEASE_VERSION ($RELEASE_BUILD_NUMBER)")
abort "publisher must bind the run to the Release workflow path" unless publish_run.include?("validation_workflow_path\" == \".github/workflows/release.yml")
abort "publisher must not use run name for Release identity" if publish_run.include?("actions/runs/$VALIDATION_RUN_ID\" --jq '.name'")
abort "publisher must verify an existing tag is annotated" unless publish_run.include?("existing_tag_type\" == \"tag")
abort "publisher must verify an existing tag target" unless publish_run.include?("existing_tag_target_type\" == \"commit") && publish_run.include?("existing_tag_commit\" == \"$RELEASE_SHA")
abort "publisher must reject a published or mismatched release" unless publish_run.include?("existing_release_draft\" == \"true") && publish_run.include?("Existing release for $tag is not a matching draft.")
abort "publisher must refresh a matching draft" unless publish_run.match?(/gh release edit \"\$tag\"[\s\\]+--draft/m) && publish_run.include?("--notes-file")
abort "publisher must upload assets idempotently" unless publish_run.include?("gh release upload \"$tag\" --clobber")
abort "publisher must create a draft release" unless publish_run.match?(/gh release create \"\$tag\"[\s\\]+--draft[\s\\]+--verify-tag/m)
RUBY

printf 'PASS: publish draft release workflow\n'
