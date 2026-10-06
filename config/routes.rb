# frozen_string_literal: true

# The route table is one declarative list (each block documents its own
# reason to exist), so the block-length budget does not apply.
# rubocop:disable Metrics/BlockLength
Decidim::ContractsSk::Engine.routes.draw do
  # Admin routes (declared before the public /:id catch-all so that the
  # admin namespace is matched first). Contract records have no :show — they
  # are edited, not displayed — and no :destroy — deletion is not part of
  # the workflow yet. Parties are managed per contract through the nested
  # resource below, which carries the full add/edit/remove surface.
  namespace :admin do
    # Admin landing page (civora-org/civora-platform#126): the role holder's
    # overview — what waits for them, the state counts, the CRZ deadline
    # watch and the last audit events. `root` inside the namespace gives
    # GET /admin (helper admin_root_path); it must precede the public
    # /:id catch-all like the rest of the namespace.
    root to: "dashboard#show"

    # Spreadsheet bulk import (civora-org/civora-platform#129): a GET upload
    # form, a stateless POST dry run (writes nothing) and a POST that
    # re-validates the posted text and imports it. Declared before the
    # contracts resource so "import" is never read as a record id.
    get "contracts/import", to: "contract_imports#new", as: :new_contract_import
    post "contracts/import/preview", to: "contract_imports#preview", as: :preview_contract_import
    post "contracts/import", to: "contract_imports#create", as: :contract_imports

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

      # CRZ filing confirmation (civora-org/civora-platform#125): a GET
      # form + read-only side-by-side preview (?crz_id=, writes nothing) and
      # a POST that verifies and stamps the filing. Declared explicitly —
      # NOT a lifecycle event, so outside the derivation above (the
      # crz_handoff pair's precedent): same path, two verbs, two actions.
      member do
        get :crz_filing, action: :crz_filing, as: :crz_filing
        post :crz_filing, action: :confirm_crz_filing, as: :confirm_crz_filing
      end

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

      # Internal review notes (civora-org/civora-platform#128): the private
      # thread role holders keep on a record. Append-only like the audit
      # trail, so the route set is the thread page (index) and the append
      # (create) only — no edit/update/destroy. Never public: nothing under
      # the public routes renders a note.
      resources :notes, only: %i[index create]
    end

    # Read-only audit-trail viewer (civora-org/civora-platform#92): one
    # org-level index over the append-only AuditEvent trail, optionally
    # filtered to one contract through ?contract_id= (a GET param, not a
    # nested route — the trail is organization-scoped first; the contract
    # is only a filter). Index only — the trail is never writable and never
    # deletable through the model (AuditEvent#readonly?), so there is no
    # other action to expose.
    resources :audit_events, only: :index

    # Role administration (civora-org/civora-platform#112, parent #95): the
    # role-holder list (index), the grant screen (new), a user search that
    # renders it with candidates (collection POST - the query can be an
    # email, so it never travels in a URL), the grant (create) and the
    # revoke (destroy). No show/edit/update: a grant is added or removed,
    # never edited.
    resources :user_roles, only: %i[index new create destroy] do
      collection { post :search }
    end
  end

  # Open-data export (civora-org/civora-platform#119): the format segment is
  # REQUIRED and limited to csv|json, so /export, /export.xml and friends
  # never match here and fall through to the /:id catch-all below (a plain
  # 404, like any unknown id). Declared before the catch-all for that reason.
  get "/export", to: "open_data#export", as: :export, format: true,
                 constraints: { format: /csv|json/ }

  # Atom feed of newly published contracts (civora-org/civora-platform#120):
  # the format segment is REQUIRED and limited to atom, so /feed, /feed.rss
  # and friends fall through to the /:id catch-all below (a plain 404).
  get "/feed", to: "feeds#show", as: :feed, format: true,
               constraints: { format: "atom" }

  # XML sitemap of the published contracts (civora-org/civora-platform#122):
  # the format segment is REQUIRED and limited to xml, so /sitemap alone and
  # /sitemap.json fall through to the /:id catch-all (a plain 404). It lives
  # under the mount (e.g. /contracts/sitemap.xml), never at the host root,
  # where a host-level /sitemap.xml may already exist.
  get "/sitemap", to: "sitemaps#show", as: :sitemap, format: true,
                  constraints: { format: "xml" }

  # Supplier page (civora-org/civora-platform#117): every published contract
  # of one counterparty, keyed by its 8-digit IČO. No format segment and the
  # IČO is constrained to exactly eight ASCII digits, so /suppliers/abc and
  # 7- or 9-digit values never reach the controller (a routing 404), and the
  # leading zeros survive (the segment is a string, never an integer).
  # Declared before the /:id catch-all (/suppliers alone still falls to it).
  get "/suppliers/:ico", to: "suppliers#show", as: :supplier, format: false,
                         constraints: { ico: Decidim::ContractsSk::ICO_PATTERN }

  # Public statistics page (civora-org/civora-platform#118): aggregates over
  # the published records. No format segment, no params. Declared before the
  # /:id catch-all, which would otherwise treat "statistics" as a contract id.
  get "/statistics", to: "statistics#show", as: :statistics, format: false

  # Public routes — the mount point is the catalogue itself
  root to: "contracts#index", as: :contracts
  get "/:id", to: "contracts#show", as: :contract
end
# rubocop:enable Metrics/BlockLength
