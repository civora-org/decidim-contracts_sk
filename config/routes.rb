# frozen_string_literal: true

Decidim::ContractsSk::Engine.routes.draw do
  # Admin routes (declared before the public /:id catch-all so that the
  # admin namespace is matched first). Contract records have no :show — they
  # are edited, not displayed — and no :destroy — deletion is not part of
  # the workflow yet. Parties are managed per contract through the nested
  # resource below, which carries the full add/edit/remove surface.
  namespace :admin do
    resources :contracts, only: %i[index new create edit update] do
      # CRZ single-record import (ADR-008, civora-org/civora-platform#86):
      # one collection POST taking a :source_id (CRZ numeric id) param —
      # not tied to an existing record, so deliberately a collection route
      # and outside the lifecycle derivation below.
      collection { post :import_crz }

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

      # Manual CRZ-handoff export (M02-05-C, civora-org/civora-platform#74):
      # a GET streams the generated handoff PDF, a POST generates (or
      # regenerates, replacing) it. Declared explicitly — this is NOT a
      # lifecycle event, so it deliberately sits outside the derivation
      # above. Same path, two verbs, two explicit actions, `as:`-named so
      # each helper reads as its action.
      member do
        get :crz_handoff, action: :download_crz_handoff, as: :download_crz_handoff
        post :crz_handoff, action: :generate_crz_handoff, as: :generate_crz_handoff
      end

      # ADR-007 privacy-redaction confirmation (civora-org/civora-platform
      # #91): one member POST stamping the confirmation that personal data
      # was redacted — the hard precondition of the publish transition.
      # Declared explicitly — NOT a lifecycle event, so deliberately outside
      # the derivation above (same reasoning as the CRZ-handoff pair).
      member { post :confirm_redaction }

      # Per-contract party management (civora-org/civora-platform#76):
      # dedicated nested pages (index/new/edit + destroy), deliberately no
      # nested-form JS. Tenancy is derived through the parent contract; the
      # controllers load both records from tenant-scoped associations before
      # the permission check.
      resources :parties, only: %i[index new create edit update destroy]

      # Per-contract document management (M02-05-A0,
      # civora-org/civora-platform#73): nested like the parties, but with no
      # :index — a document's replace (edit + PATCH/PUT :update) and remove
      # (:destroy) controls live on the contract's own edit page, and the
      # public catalogue lists documents for published records. Same tenancy
      # and permission mechanics as the parties.
      resources :documents, only: %i[new create edit update destroy]

      # Per-contract amendment management (M02-05-B,
      # civora-org/civora-platform#65): nested like the parties, with the
      # full version-history surface (index/new/edit + update/destroy) plus
      # one explicit member POST for the publish event — the same
      # one-POST-per-event convention as the lifecycle transitions above.
      # Draft amendments are edited here; published ones are immutable
      # (ADR-006) and render in the public catalogue's version history.
      resources :amendments, only: %i[index new create edit update destroy] do
        member { post :publish }
      end

      # Per-contract project/result link management (M01-87,
      # civora-org/civora-platform#87): nested like the siblings, but with
      # only the create/destroy surface — links carry no editable content,
      # so there is no index/new/edit/update page (the contract's edit page
      # lists the links and hosts the add form, document-style). Tenancy is
      # derived through the parent contract; the controller loads both
      # records from tenant-scoped associations before the permission check.
      resources :links, only: %i[create destroy]
    end
  end

  # Public routes — the mount point is the catalogue itself
  root to: "contracts#index", as: :contracts
  get "/:id", to: "contracts#show", as: :contract
end
