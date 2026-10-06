# frozen_string_literal: true

require "spec_helper"

# Host apps copy the engine's migrations verbatim with their original
# timestamps, and Rails 7.2 refuses to load a schema whose migrations are
# dated more than a day in the future (ActiveRecord::InvalidMigrationTimestampError,
# activerecord-7.2 migration.rb). v1.7.0 shipped three such migrations and
# broke the host's CI; this keeps a new one from being released.
RSpec.describe "engine migration timestamps" do # rubocop:disable RSpec/DescribeClass
  migration_files = Dir[File.expand_path("../../../db/migrate/*.rb", __dir__)]

  it "finds the engine migrations" do
    expect(migration_files).not_to be_empty
  end

  it "dates no migration more than a day in the future" do
    limit = (Time.now.utc + 1.day).strftime("%Y%m%d%H%M%S").to_i
    future = migration_files.map { |path| File.basename(path) }
                            .select { |name| name[/\A\d{14}/].to_i > limit }
    expect(future).to be_empty
  end

  it "keeps every timestamp unique" do
    versions = migration_files.map { |path| File.basename(path)[/\A\d{14}/] }
    expect(versions.uniq.size).to eq(versions.size)
  end
end
