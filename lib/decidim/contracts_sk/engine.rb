# frozen_string_literal: true

require "rails/engine"

module Decidim
  module ContractsSk
    # Rails Engine for the Decidim ContractsSk module.
    # Registers autoload paths, locales, and integrates the module
    # into the Decidim application lifecycle.
    class Engine < ::Rails::Engine
      isolate_namespace Decidim::ContractsSk

      initializer "decidim_contracts_sk.autoload" do
        config.autoload_paths += %W[
          #{config.root}/app/commands
          #{config.root}/app/events
          #{config.root}/app/forms
          #{config.root}/app/permissions
        ]
      end

      initializer "decidim_contracts_sk.i18n" do
        config.i18n.load_path += Dir[
          config.root.join("config", "locales", "*.yml").to_s
        ]
      end
    end
  end
end
