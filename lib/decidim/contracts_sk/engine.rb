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
          #{config.root}/app/pdfs
          #{config.root}/app/permissions
        ]
      end

      initializer "decidim_contracts_sk.i18n" do
        config.i18n.load_path += Dir[
          config.root.join("config", "locales", "*.yml").to_s
        ]
      end

      # Navigation integration (civora-org/civora-platform#86c): the public
      # catalogue into Decidim's main menu (and its mobile registry twin),
      # mirroring how Decidim's own modules hook their menus (see
      # decidim-core engine.rb, initializer "decidim_core.menu"). The
      # registration blocks are only evaluated at render time, so nothing
      # here needs the routes or a database at boot.
      initializer "decidim_contracts_sk.menu" do
        Decidim::ContractsSk::Menu.register_menu!
      end

      # The admin sidebar entry (the :admin_menu_modules registry shared by
      # every Decidim content module), visibility-gated to engine role
      # holders through the config-time role resolver seam.
      initializer "decidim_contracts_sk.admin_menu" do
        Decidim::ContractsSk::Menu.register_admin_menu_modules!
        Decidim::ContractsSk::Menu.register_admin_roles_item!
      end

      # Account-area entry link to the engine admin for role holders who are
      # not Decidim admins (civora-org/civora-platform#161).
      initializer "decidim_contracts_sk.user_menu" do
        Decidim::ContractsSk::Menu.register_user_menu!
      end
    end
  end
end
