# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the engine's navigation integration
# (civora-org/civora-platform#86c).
#
# What is real here: the pinned-gem menu machinery (Decidim::MenuRegistry,
# Decidim::Menu, Decidim::MenuItem — required pin-point by the dummy
# harness) and the engine's registration blocks, which the dummy boot
# executed through the engine's initializers.
#
# What is mirrored: the registration blocks are evaluated the way
# Decidim::MenuPresenter does at render time (Decidim::Menu#build_for,
# instance_exec'd against a view context — decidim-core menu_presenter.rb
# evaluates exactly like this), against a minimal view-context stand-in that
# provides the two methods the blocks touch: the engine route helper and
# current_user. The engine's real isolated url_helpers answer the route
# calls, so the asserted URLs are the engine's true paths.
#
# Registry note: the offline harness never boots decidim-core's engine, so
# the :menu / :mobile_menu / :admin_menu_modules registries contain ONLY the
# engine's own items — which is what makes the exact-item assertions
# deterministic here.
# ---------------------------------------------------------------------------

require "spec_helper"

# Minimal stand-in for a Decidim user, carrying only what the engine's
# default role resolver consults (same shape as the SpecUser of the
# permissions spec).
MenuSpecUser = Struct.new(:admin, :admin_terms_accepted, keyword_init: true) do
  def admin?
    admin
  end

  def admin_terms_accepted?
    admin_terms_accepted
  end
end

# Minimal view-context stand-in for build_for: provides the methods the
# registration blocks touch. The engine's real isolated url_helpers module
# answers the route calls; current_organization mirrors the Decidim view
# helper the admin block consults.
MenuSpecViewContext = Struct.new(:routes, :current_user, :current_organization, keyword_init: true) do
  def decidim_contracts_sk
    routes
  end
end

# A context WITHOUT the current_organization helper (the respond_to? guard
# in the admin registration block must degrade to nil, not raise).
MenuSpecBareContext = Struct.new(:routes, :current_user) do
  def decidim_contracts_sk
    routes
  end
end

# View-context stand-in for the :user_menu entry, which also asks the view's
# allowed_to? helper whether Decidim already offers its own admin link.
MenuSpecAccountContext = Struct.new(:routes, :current_user, :decidim_admin_link, keyword_init: true) do
  def decidim_contracts_sk
    routes
  end

  def allowed_to?(action, subject, *)
    action == :read && subject == :admin_dashboard && decidim_admin_link
  end
end

RSpec.describe Decidim::ContractsSk::Menu do
  let(:routes) { Decidim::ContractsSk::Engine.routes.url_helpers }

  # Builds a menu the way the render-time presenter does and returns its
  # visible, position-sorted items (Decidim::Menu#items). A prebuilt
  # :context overrides the default stand-in (used for contexts lacking
  # current_organization).
  def items_for(registry_name, current_user: nil, context: nil)
    context ||= MenuSpecViewContext.new(routes: routes, current_user: current_user)

    menu = Decidim::Menu.new(registry_name)
    menu.build_for(context)
    menu.items
  end

  # Swaps the config seam for the duration of the block, restoring the
  # ambient resolver afterwards (config-time-only seam: tests restore it).
  def swap_resolver(resolver)
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = resolver
    yield
  ensure
    Decidim::ContractsSk.role_resolver = original
  end

  # A resolver double that records its context argument into +captured+ and
  # grants +roles+ — for passthrough assertions on the resolver context.
  def recording_resolver(captured, roles)
    lambda do |_user, context|
      captured << context
      roles
    end
  end

  # Grants engine roles only for one specific organization context.
  def org_scoped_resolver
    ->(_user, org) { org == :municipality ? %i[editor] : [] }
  end

  describe "registry registration (engine initializers ran at boot)" do
    it "registers the public main menu" do
      expect(Decidim::MenuRegistry.find(:menu)).to be_a(Decidim::MenuRegistry)
    end

    it "registers the mobile menu" do
      expect(Decidim::MenuRegistry.find(:mobile_menu)).to be_a(Decidim::MenuRegistry)
    end

    it "registers the admin modules menu (the Decidim admin sidebar section)" do
      expect(Decidim::MenuRegistry.find(:admin_menu_modules)).to be_a(Decidim::MenuRegistry)
    end
  end

  describe "public main menu item (:menu)" do
    let(:items) { items_for(:menu) }
    let(:item) { items.first }

    it "is the only item in the offline registry and is always visible" do
      expect(items.length).to eq(1)
    end

    it "carries the engine-namespaced identifier" do
      expect(item.identifier).to eq(:contracts_sk)
    end

    it "carries the localized label" do
      expect(item.label).to eq("Contracts")
    end

    it "points at the public catalogue root" do
      expect(item.url).to eq(routes.contracts_path)
    end

    it "sits at the content-module slot of the menu" do
      expect(item.position).to eq(2.4)
    end

    it "highlights on the catalogue index and detail pages (prefix match)" do
      expect(item.active).to eq(:inclusive)
    end

    it "carries no icon (core main-menu convention)" do
      expect(item.icon_name).to be_nil
    end
  end

  describe "public mobile menu item (:mobile_menu)" do
    let(:items) { items_for(:mobile_menu) }
    let(:item) { items.first }

    # One deliberate mirror-matrix example: the :mobile_menu item must match
    # the :menu item field by field (registry twins, see register_menu!).
    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it "mirrors the main-menu item exactly" do
      expect(items.length).to eq(1)
      expect(item.identifier).to eq(:contracts_sk)
      expect(item.label).to eq("Contracts")
      expect(item.url).to eq(routes.contracts_path)
      expect(item.position).to eq(2.4)
      expect(item.active).to eq(:inclusive)
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
  end

  describe "admin sidebar item (:admin_menu_modules)" do
    let(:item) { items_for(:admin_menu_modules, current_user: role_holder).first }

    let(:role_holder) { MenuSpecUser.new(admin: true, admin_terms_accepted: true) }

    it "is the only visible item for an engine role holder who may not manage roles" do
      swap_resolver(->(_user, _context) { %i[editor reviewer] }) do
        holder = MenuSpecUser.new(admin: false, admin_terms_accepted: true)

        expect(items_for(:admin_menu_modules, current_user: holder).length).to eq(1)
      end
    end

    it "is visible (a MenuItem) for an engine role holder" do
      expect(item).to be_a(Decidim::MenuItem)
    end

    it "carries the engine-namespaced identifier" do
      expect(item.identifier).to eq(:contracts_sk)
    end

    it "carries the localized admin label" do
      expect(item.label).to eq("Contracts")
    end

    it "points at the admin overview (dashboard, civora-org/civora-platform#126)" do
      expect(item.url).to eq(routes.admin_root_path)
    end

    it "sits next to the other content modules" do
      expect(item.position).to eq(2.4)
    end

    it "highlights on the admin index and every nested manager page (prefix match)" do
      expect(item.active).to eq(:inclusive)
    end

    # The exact core-registered icon name: Decidim.icons.register(name:
    # "scales-2-line", ...) — decidim-core 0.31.7 lib/decidim/core/engine.rb
    # line 168 (resolved at render time through Decidim.icons.find,
    # decidim-core app/helpers/decidim/layout_helper.rb:50-51). Not invented.
    it "carries the core-registered icon" do
      expect(item.icon_name).to eq("scales-2-line")
    end
  end

  describe "role administration sidebar item (civora-org/civora-platform#112)" do
    let(:org_admin) { MenuSpecUser.new(admin: true, admin_terms_accepted: true) }

    def roles_item(user)
      items_for(:admin_menu_modules, current_user: user).find { |i| i.identifier == :contracts_sk_roles }
    end

    it "is visible to an organization admin with accepted terms" do
      expect(roles_item(org_admin)).to be_a(Decidim::MenuItem)
    end

    it "is labelled Roles and points at the role list, right after the Contracts entry" do
      item = roles_item(org_admin)

      expect([item.label, item.url, item.position > 2.4]).to eq(["Roles", routes.admin_user_roles_path, true])
    end

    it "is hidden from an engine role holder who is not an organization admin" do
      swap_resolver(->(_user, _context) { %i[editor reviewer] }) do
        expect(roles_item(MenuSpecUser.new(admin: false, admin_terms_accepted: true))).to be_nil
      end
    end

    it "is hidden from an organization admin who has not accepted the admin terms" do
      expect(roles_item(MenuSpecUser.new(admin: true, admin_terms_accepted: false))).to be_nil
    end

    it "is hidden for an anonymous visitor" do
      expect(roles_item(nil)).to be_nil
    end

    it "does not consult the role resolver (a custom resolver never confers it)" do
      swap_resolver(->(_user, _context) { %i[editor reviewer] }) do
        expect(described_class.manages_roles?(MenuSpecUser.new(admin: false, admin_terms_accepted: true))).to be(false)
      end
    end

    it "fails closed when the user object cannot answer" do
      expect(described_class.manages_roles?(Object.new)).to be(false)
    end
  end

  describe "admin item visibility (role resolver seam)" do
    let(:role_holder) { MenuSpecUser.new(admin: true, admin_terms_accepted: true) }

    # The Contracts entry only: the role-administration item has its own
    # rule (the :user_role permission, never the resolver).
    def contracts_items(user)
      items_for(:admin_menu_modules, current_user: user).select { |i| i.identifier == :contracts_sk }
    end

    it "is visible for a user granted a custom engine role" do
      swap_resolver(->(_user, _context) { %i[reviewer] }) do
        plain_user = MenuSpecUser.new(admin: false, admin_terms_accepted: false)

        expect(items_for(:admin_menu_modules, current_user: plain_user)).not_to be_empty
      end
    end

    it "is hidden for an anonymous visitor — safely, without raising" do
      expect(items_for(:admin_menu_modules, current_user: nil)).to be_empty
    end

    it "is hidden for a user the default resolver grants nothing" do
      expect(items_for(:admin_menu_modules, current_user: MenuSpecUser.new(admin: false, admin_terms_accepted: true)))
        .to be_empty
    end

    it "is hidden for an org admin who has not accepted the admin terms" do
      expect(items_for(:admin_menu_modules, current_user: MenuSpecUser.new(admin: true, admin_terms_accepted: false)))
        .to be_empty
    end

    it "is hidden when the resolver returns only foreign roles (vocabulary intersection)" do
      swap_resolver(->(_user, _context) { %i[superadmin] }) do
        expect(contracts_items(MenuSpecUser.new(admin: true, admin_terms_accepted: true))).to be_empty
      end
    end

    it "is hidden when the resolver is not callable (broken host config degrades, never raises)" do
      swap_resolver(nil) do
        expect(contracts_items(MenuSpecUser.new(admin: true, admin_terms_accepted: true))).to be_empty
      end
    end

    it "is hidden when the resolver RAISES — fail-closed, never a 500 on admin pages (M-1)" do
      swap_resolver(->(_user, _context) { raise "boom" }) do
        expect(contracts_items(role_holder)).to be_empty
      end
    end

    # The two context-capture examples below are deliberate capture-and-assert
    # pairs: the swapped resolver records its context argument, then the
    # example asserts BOTH the capture and the resulting visibility — one
    # resolver call, one story.
    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it "passes the view's current_organization to the resolver as its context (L-1)" do
      captured = []
      swap_resolver(recording_resolver(captured, %i[editor])) do
        org_context = MenuSpecViewContext.new(routes: routes, current_user: role_holder,
                                              current_organization: :the_organization)

        expect(items_for(:admin_menu_modules, context: org_context)).not_to be_empty
        expect(captured).to eq([:the_organization])
      end
    end

    it "passes nil as the resolver context when the view context has no current_organization" do
      captured = []
      swap_resolver(recording_resolver(captured, %i[editor])) do
        bare = MenuSpecBareContext.new(routes: routes, current_user: role_holder)

        expect(items_for(:admin_menu_modules, context: bare)).not_to be_empty
        expect(captured).to eq([nil])
      end
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
  end

  # civora-org/civora-platform#161 (D3 of the #108 spike): the account-area
  # entry link, shown to engine role holders Decidim does not already link to
  # the admin dashboard.
  describe "account menu entry (:user_menu)" do
    let(:plain_user) { MenuSpecUser.new(admin: false, admin_terms_accepted: false) }

    def account_items(user, decidim_admin_link: false)
      context = MenuSpecAccountContext.new(routes: routes, current_user: user,
                                           decidim_admin_link: decidim_admin_link)
      menu = Decidim::Menu.new(:user_menu)
      menu.build_for(context)
      menu.items
    end

    it "registers the user menu registry" do
      expect(Decidim::MenuRegistry.find(:user_menu)).to be_a(Decidim::MenuRegistry)
    end

    it "shows for a non-admin engine role holder, pointing at the engine admin root" do
      swap_resolver(->(_user, _context) { %i[editor] }) do
        item = account_items(plain_user).first

        expect([item.identifier, item.url, item.label])
          .to eq([:contracts_sk_admin, routes.admin_root_path, "Contracts administration"])
      end
    end

    it "is hidden for a user without an engine role" do
      expect(account_items(plain_user)).to be_empty
    end

    it "is hidden for an anonymous visitor" do
      expect(account_items(nil)).to be_empty
    end

    it "is hidden when Decidim already offers the admin link (no duplicate for admins)" do
      swap_resolver(->(_user, _context) { %i[editor reviewer] }) do
        expect(account_items(plain_user, decidim_admin_link: true)).to be_empty
      end
    end

    it "is hidden when the resolver raises (fail-closed)" do
      swap_resolver(->(_user, _context) { raise "boom" }) do
        expect(account_items(plain_user)).to be_empty
      end
    end
  end

  describe ".holds_engine_role?" do
    it "answers true for a default-resolver org admin with accepted terms" do
      user = MenuSpecUser.new(admin: true, admin_terms_accepted: true)

      expect(described_class.holds_engine_role?(user)).to be(true)
    end

    it "answers false for nil (anonymous)" do
      expect(described_class.holds_engine_role?(nil)).to be(false)
    end

    it "answers false for a plain user" do
      user = MenuSpecUser.new(admin: false, admin_terms_accepted: true)

      expect(described_class.holds_engine_role?(user)).to be(false)
    end

    it "answers false for a non-callable resolver (fail-closed)" do
      swap_resolver(nil) do
        user = MenuSpecUser.new(admin: true, admin_terms_accepted: true)

        expect(described_class.holds_engine_role?(user)).to be(false)
      end
    end

    it "answers false when the resolver raises (fail-closed, M-1)" do
      swap_resolver(->(_user, _context) { raise "boom" }) do
        user = MenuSpecUser.new(admin: true, admin_terms_accepted: true)

        expect(described_class.holds_engine_role?(user)).to be(false)
      end
    end

    # Capture-and-assert pair (see the sibling group above): one resolver
    # call, then both the capture and the outcome are asserted.
    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it "forwards the organization argument as the resolver context (L-1)" do
      captured = []
      swap_resolver(recording_resolver(captured, %i[editor])) do
        user = MenuSpecUser.new(admin: false, admin_terms_accepted: false)

        expect(described_class.holds_engine_role?(user, :the_organization)).to be(true)
        expect(captured).to eq([:the_organization])
      end
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength

    it "answers true for an org-scoped resolver when the organization matches" do
      swap_resolver(org_scoped_resolver) do
        user = MenuSpecUser.new(admin: false, admin_terms_accepted: false)

        expect(described_class.holds_engine_role?(user, :municipality)).to be(true)
      end
    end

    it "answers false for an org-scoped resolver when the organization differs" do
      swap_resolver(org_scoped_resolver) do
        user = MenuSpecUser.new(admin: false, admin_terms_accepted: false)

        expect(described_class.holds_engine_role?(user, :other_town)).to be(false)
      end
    end

    it "answers false when the resolver grants only foreign roles" do
      swap_resolver(->(_user, _context) { %i[admin superadmin] }) do
        user = MenuSpecUser.new(admin: true, admin_terms_accepted: true)

        expect(described_class.holds_engine_role?(user)).to be(false)
      end
    end
  end
end
