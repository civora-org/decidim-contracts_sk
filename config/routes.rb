# frozen_string_literal: true

Decidim::ContractsSk::Engine.routes.draw do
  # Admin routes (declared before the public /:id catch-all so that the
  # admin namespace is matched first). No :show — admin records are edited,
  # not displayed; no :destroy — deletion is not part of the workflow yet.
  namespace :admin do
    resources :contracts, only: %i[index new create edit update]
  end

  # Public routes — the mount point is the catalogue itself
  root to: "contracts#index", as: :contracts
  get "/:id", to: "contracts#show", as: :contract
end
