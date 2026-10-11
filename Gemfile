# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in decidim-contracts_sk.gemspec

# Select the Decidim line to resolve against (CI matrix); unset keeps the
# gemspec range, i.e. the newest line the local Ruby supports.
#   DECIDIM_VERSION=0.31 bundle install   # Ruby 3.3
#   DECIDIM_VERSION=0.32 bundle install   # Ruby 3.4
if ENV["DECIDIM_VERSION"]
  gem "decidim-admin", "~> #{ENV.fetch("DECIDIM_VERSION")}.0"
  gem "decidim-core", "~> #{ENV.fetch("DECIDIM_VERSION")}.0"
end
gemspec

gem "irb"
gem "rake", "~> 13.0"
