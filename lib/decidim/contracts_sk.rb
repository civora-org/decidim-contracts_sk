# frozen_string_literal: true

require_relative "contracts_sk/version"

module Decidim
  module ContractsSk
    class Error < StandardError; end
  end
end

require_relative "contracts_sk/engine" if defined?(Rails)
