# frozen_string_literal: true

Decidim::ContractsSk::Engine.routes.draw do
  # Public routes
  resources :contracts, only: %i[index show]

  # Admin routes
  namespace :admin do
    resources :contracts
  end
end
