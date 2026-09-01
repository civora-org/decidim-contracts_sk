# frozen_string_literal: true

require_relative "lib/decidim/contracts_sk/version"

Gem::Specification.new do |spec|
  spec.name = "decidim-contracts_sk"
  spec.version = Decidim::ContractsSk::VERSION
  spec.authors = ["Denys Kozlov"]
  spec.email = ["denys.kozlov.work@gmail.com"]

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
  spec.add_dependency "decidim-admin", "~> 0.31.0"
  spec.add_dependency "decidim-core", "~> 0.31.0"

  # Development dependencies
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "rubocop-rails", "~> 2.20"
  # rubocop-rspec 2.31 pulls rubocop-rspec_rails 2.29, whose inject_defaults!
  # API was removed in rubocop 1.90; 3.x loads via the plugins mechanism.
  spec.add_development_dependency "rubocop-rspec", "~> 3.0"
end
