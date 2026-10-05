# frozen_string_literal: true

require_relative "lib/decidim/contracts_sk/version"

Gem::Specification.new do |spec|
  spec.name = "decidim-contracts_sk"
  spec.version = Decidim::ContractsSk::VERSION
  spec.authors = ["Denys Kozlov"]
  spec.email = ["denys@civora.sk"]

  spec.summary = "Decidim engine for Slovak public contracts workflow and catalogue."
  spec.description = "A Decidim module that provides a structured workflow for drafting, reviewing " \
                     "and publishing public contract records, together with a public catalogue " \
                     "for Slovak municipalities and public-sector organisations."
  spec.homepage = "https://github.com/civora-org/decidim-contracts_sk"
  spec.license = "AGPL-3.0"

  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end

  spec.require_paths = ["lib"]

  # Runtime dependencies
  # 0.31.x is the current Decidim major. It supports Ruby 3.3 (verified
  # against the installed 0.31.7 gemset), and this engine targets it
  # (civora-org/civora-platform#46).
  # Floor is 0.31.5: earlier 0.31.x carries CVE-2026-45573 (decidim-core push
  # subscriptions SSRF, Medium), and Decidim's meta-gems pin each other with
  # `=`, so a loose floor lets fresh resolutions settle on unpatched lines.
  # Pure-Ruby PDF generation for the manual CRZ-handoff export
  # (M02-05-C, civora-org/civora-platform#74). Pinned to 2.5.x — the
  # current stable line (2.5.0 verified installable offline).
  spec.add_dependency "prawn", "~> 2.5.0"

  # csv left the default gems in Ruby 3.4 (a bundled gem: not loadable under
  # Bundler unless declared) and the open-data export requires it
  # (civora-org/civora-platform#119). 3.0 is the first release with the
  # generate_line / col_sep API the export uses on every supported Ruby.
  spec.add_dependency "csv", "~> 3.0"

  spec.add_dependency "decidim-admin", "~> 0.31.5"
  spec.add_dependency "decidim-core", "~> 0.31.5"

  # json 3.0 removed the `quirks_mode` keyword that ActiveSupport 7.2 still
  # passes to both JSON.parse and JSON.generate
  # (activesupport-7.2.2.2 lib/active_support/json/{decoding,encoding}.rb),
  # so a fresh resolution settling on json 3.x breaks every JSON
  # serialization path at runtime — ActiveStorage blob metadata, json
  # columns, cache entries (first observed as CI :db-group ArgumentErrors,
  # "unknown keyword: quirks_mode"). Cap below 3.0 until the pinned Rails
  # line ships json-3 compatibility; drop this constraint with it.
  spec.add_dependency "json", ">= 2.0", "< 3.0"

  # Development dependencies
  spec.add_development_dependency "bundler-audit", "~> 0.9"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "rubocop-rails", "~> 2.20"
  # rubocop-rspec 2.31 pulls rubocop-rspec_rails 2.29, whose inject_defaults!
  # API was removed in rubocop 1.90; 3.x loads via the plugins mechanism.
  spec.add_development_dependency "rubocop-rspec", "~> 3.0"
  # Only needed by the opt-in CONTRACTS_SK_DB=1 specs (:db groups run against
  # an in-memory SQLite adapter; see spec/decidim/contracts_sk/contract_spec.rb).
  spec.add_development_dependency "sqlite3", "~> 2.0"
end
