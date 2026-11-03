# frozen_string_literal: true

# Every icon the engine names must be registered by the pinned Decidim gems.
# An unregistered name is a deprecation warning in development and an
# "Icon ... not found" error in the host's test runs on Decidim 0.32
# (v1.10.0 shipped "building-line" for the organisation header item). The
# offline harness never boots decidim-core's engine, so the registry is read
# from the gems' own registration calls rather than from Decidim.icons.

require "spec_helper"

RSpec.describe Decidim::ContractsSk::Menu do
  registered = %w[decidim-core decidim-admin].flat_map do |gem_name|
    spec = Gem.loaded_specs.fetch(gem_name)
    Dir[File.join(spec.full_gem_path, "{lib,config,app}", "**", "*.rb")].flat_map do |file|
      File.read(file).scan(/register\(\s*name:\s*"([a-z0-9-]+)"/).flatten
    end
  end.uniq

  engine_root = File.expand_path("../../..", __dir__)
  used = Dir[File.join(engine_root, "{app,lib}", "**", "*.{rb,erb}")].flat_map do |file|
    File.read(file).scan(/"([a-z0-9]+(?:-[a-z0-9]+)*-(?:line|fill))"/).flatten
  end.uniq

  it "reads the core icon registrations" do
    expect(registered).to include("government-line")
  end

  it "finds the icons the engine names" do
    expect(used).not_to be_empty
  end

  used.each do |name|
    it "names #{name}, which decidim-core or decidim-admin registers" do
      expect(registered).to include(name)
    end
  end
end
