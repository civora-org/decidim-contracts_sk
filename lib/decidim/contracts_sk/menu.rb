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

      # The sidebar entry points at the admin overview (dashboard, civora-org/
      # civora-platform#126); with active: :inclusive (a path-prefix match) it
      # stays highlighted on every engine admin page (contracts, parties,
      # amendments, audit trail, ...), since they all live under the same
      # /admin prefix.
      #
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
                        decidim_contracts_sk.admin_root_path,
                        icon_name: "scales-2-line",
                        position: POSITION,
                        active: :inclusive,
                        if: Decidim::ContractsSk::Menu.holds_engine_role?(current_user, organization)
        end
      end

      # Role administration sidebar item (civora-org/civora-platform#112):
      # visible only to users the :user_role permission admits, decided by
      # the engine's own Permissions class rather than the view's allowed_to?
      # (the sidebar also renders on Decidim's own admin pages, whose
      # permission chain does not include the engine).
      def self.register_admin_roles_item!
        Decidim.menu :admin_menu_modules do |menu|
          menu.add_item :contracts_sk_roles,
                        I18n.t("menu.admin_user_roles", scope: "decidim.contracts_sk"),
                        decidim_contracts_sk.admin_user_roles_path,
                        icon_name: "user-settings-line",
                        position: POSITION + 0.01,
                        active: :inclusive,
                        if: Decidim::ContractsSk::Menu.manages_roles?(current_user)
        end
      end

      # The entry link for engine role holders who are NOT Decidim admins
      # (civora-org/civora-platform#161, D3 of the #108 spike). Decidim's own
      # admin links (header dropdown, admin bar, /account sidebar) are gated
      # on :read :admin_dashboard, which such users lack, so nothing led them
      # to the engine admin.
      #
      # Placement: the :user_menu registry, the Decidim-native extension point
      # rendered as the account-area navigation (decidim-core
      # lib/decidim/core/menu.rb register_user_menu!, rendered by
      # app/views/layouts/decidim/shared/_layout_user_profile.html.erb). The
      # header user dropdown is hard-coded ERB without a registry, so reaching
      # it would mean overriding a core view.
      #
      # Visibility: holds an engine role AND is not already offered Decidim's
      # own admin link (allowed_to?(:read, :admin_dashboard), the exact test
      # decidim-core's _user_menu.html.erb applies), so engine admins and
      # users with a Decidim admin role keep their single, existing entry.
      # Evaluated per render in the view context; fail-closed like the other
      # registrations (holds_engine_role? never raises).
      def self.register_user_menu!
        Decidim.menu :user_menu do |menu|
          menu.add_item :contracts_sk_admin,
                        I18n.t("menu.user_admin_contracts", scope: "decidim.contracts_sk"),
                        decidim_contracts_sk.admin_root_path,
                        position: 1.8,
                        active: :inclusive,
                        if: Decidim::ContractsSk::Menu.account_entry_visible?(self)
        end
      end

      # The :user_menu visibility test, evaluated against the rendering view
      # (respond_to? guards keep stand-in contexts safe).
      def self.account_entry_visible?(view)
        organization = view.respond_to?(:current_organization) ? view.current_organization : nil
        decidim_admin_link = view.respond_to?(:allowed_to?) && view.allowed_to?(:read, :admin_dashboard)

        holds_engine_role?(view.current_user, organization) && !decidim_admin_link
      end

      # True when the :user_role permission admits the user to the role
      # screens (admin scope, :read) - asked of the engine's Permissions
      # class itself, the single source of the rule (org admin with accepted
      # admin terms). Fail-closed like holds_engine_role?: nil users and any
      # error answer false, so menu rendering never raises.
      def self.manages_roles?(user)
        return false if user.nil?

        action = Decidim::PermissionAction.new(scope: :admin, action: :read, subject: :user_role)
        Decidim::ContractsSk::Permissions.new(user, action, {}).permissions.allowed?
      rescue StandardError
        false
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
