# frozen_string_literal: true

Decidim::ContractsSk::Engine.routes.draw do
  # Admin routes (declared before the public /:id catch-all so that the
  # admin namespace is matched first). No :show — admin records are edited,
  # not displayed; no :destroy — deletion is not part of the workflow yet.
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
    end
  end

  # Public routes — the mount point is the catalogue itself
  root to: "contracts#index", as: :contracts
  get "/:id", to: "contracts#show", as: :contract
end
