# frozen_string_literal: true

require_relative "contract_lifecycle"

module Decidim
  module ContractsSk
    # Menu registrations for the engine, following the Decidim module
    # convention (see Decidim::ParticipatoryProcesses::Menu and
    # Decidim::Assemblies::Menu in the pinned gem): class-level +register_*!
    # methods hooked from engine initializers, each registering a block into
    # a Decidim::MenuRegistry through Decidim.menu.
    #
    # The registration blocks are stored at boot and only EVALUATED at render
    # time, instance_exec'd in the view context (Decidim::Menu#build_for) —
    # so the route helpers and current_user inside them resolve per request
    # and nothing here touches the database or the routes at boot.
    class Menu
      # Position convention: the content-module cluster of the public main
      # menu and of the admin "modules" section starts at 2 (participatory
      # processes) / 2.2 (assemblies); the contracts catalogue slots right
      # after it. Hosts can re-order per Decidim menu conventions
      # (Decidim::Menu#move or their own registrations).
      POSITION = 2.4

      # Public main menu (desktop nav, breadcrumb dropdown and footer render
      # the :menu registry; the mobile menu-bar dropdown renders the separate
      # :mobile_menu registry — core modules register the identical item in
      # both, and so do we: one shared registration, two registries).
      # Unconditional visibility: the catalogue has a designed empty state,
      # so the entry shows even before the first record is published.
      #
      # The add_item call stays INLINE in the registration block on purpose:
      # the block is instance_exec'd in the view context at render time
      # (Decidim::Menu#build_for), so the route helper inside it must resolve
      # against the VIEW — extracting it into a class method would change
      # self and break the helper lookup.
      def self.register_menu!
        register_catalogue_item_in(:menu)
        register_catalogue_item_in(:mobile_menu)
      end

      # The shared catalogue registration — one item definition, consumed by
      # both the :menu and :mobile_menu registries above. Called with the
      # implicit class receiver from register_menu!, so it may stay private.
      def self.register_catalogue_item_in(registry_name)
        Decidim.menu registry_name do |menu|
          menu.add_item :contracts_sk,
                        I18n.t("menu.contracts", scope: "decidim.contracts_sk"),
                        decidim_contracts_sk.contracts_path,
                        position: POSITION,
                        active: :inclusive
        end
      end
      private_class_method :register_catalogue_item_in

      # Decidim admin sidebar — the "modules" section (:admin_menu_modules
      # registry, rendered by Decidim::Admin::MenuHelper#main_menu_modules),
      # the same registry every Decidim content module registers into.
      #
      # Visibility: only users holding at least one engine role (the same
      # role_resolver seam the engine's Permissions class consults,
      # intersected with the engine's role vocabulary). Evaluated at render
      # time; degrades safely — an anonymous visitor (current_user nil) or a
      # broken resolver simply hides the entry, never raises.
      def self.register_admin_menu_modules!
        Decidim.menu :admin_menu_modules do |menu|
          # View-side values — the block is instance_exec'd in the view
          # context at render time; respond_to? guards the (harness/stand-in)
          # contexts that lack the Decidim organization helper.
          organization = respond_to?(:current_organization) ? current_organization : nil

          menu.add_item :contracts_sk,
                        I18n.t("menu.admin_contracts", scope: "decidim.contracts_sk"),
                        decidim_contracts_sk.admin_contracts_path,
                        icon_name: "scales-2-line",
                        position: POSITION,
                        active: :inclusive,
                        if: Decidim::ContractsSk::Menu.holds_engine_role?(current_user, organization)
        end
      end

      # True when the user holds at least one engine role through the
      # config-time role resolver — the same seam and intersection the
      # engine's Permissions class applies (Permissions#roles_for_user).
      # +organization+ (the view's current_organization, or nil) is passed
      # through as the resolver's context argument, so org-scoped host
      # resolvers work.
      #
      # Fail-closed on purpose — menu rendering sits in the whole admin
      # layout and must never raise: nil users, non-callable resolvers AND
      # resolvers that RAISE all answer false (a broken host resolver hides
      # the entry, it never 500s admin pages).
      def self.holds_engine_role?(user, organization = nil)
        return false if user.nil?

        resolver = Decidim::ContractsSk.role_resolver
        return false unless resolver.respond_to?(:call)

        roles = begin
          Array(resolver.call(user, organization))
        rescue StandardError
          []
        end

        (roles & ContractLifecycle::ROLES).any?
      end
    end
  end
end
