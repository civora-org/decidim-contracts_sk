# frozen_string_literal: true

Decidim::ContractsSk::Engine.routes.draw do
  # Admin routes (declared before the public /:id catch-all so that the
  # admin namespace is matched first). Contract records have no :show — they
  # are edited, not displayed — and no :destroy — deletion is not part of
  # the workflow yet. Parties are managed per contract through the nested
  # resource below, which carries the full add/edit/remove surface.
  namespace :admin do
    resources :contracts, only: %i[index new create edit update] do
      # Lifecycle-transition member routes (civora-org/civora-platform#59),
      # derived from the lifecycle table — the single source of truth — never
      # hand-enumerated, so table additions are picked up verbatim. The
      # derivation is duplicated on purpose (layers stay decoupled) and is
      # spec-pinned in both directions in
      # spec/decidim/contracts_sk/engine_routing_spec.rb.
      Decidim::ContractsSk::ContractLifecycle::TRANSITIONS.values
                                                          .flat_map(&:keys)
                                                          .uniq.sort.each do |event|
        member { post event }
      end

      # Per-contract party management (civora-org/civora-platform#76):
      # dedicated nested pages (index/new/edit + destroy), deliberately no
      # nested-form JS. Tenancy is derived through the parent contract; the
      # controllers load both records from tenant-scoped associations before
      # the permission check.
      resources :parties, only: %i[index new create edit update destroy]
    end
  end

  # Public routes — the mount point is the catalogue itself
  root to: "contracts#index", as: :contracts
  get "/:id", to: "contracts#show", as: :contract
end
