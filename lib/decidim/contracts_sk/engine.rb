# frozen_string_literal: true

require "rails/engine"

module Decidim
  module ContractsSk
    class Engine < ::Rails::Engine
      isolate_namespace Decidim::ContractsSk

      initializer "decidim_contracts_sk.autoload" do
        config.autoload_paths += %W[
          #{config.root}/app/commands
          #{config.root}/app/events
          #{config.root}/app/forms
        ]
      end
    end
  end
end
