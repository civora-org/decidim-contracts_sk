# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline locale-contract specs for civora-org/civora-platform#39
# (M01-01-G: Add locales).
#
# Loading pattern (no dummy Rails app, no engine boot):
#
#   1. both locale files are parsed with YAML.safe_load for structural
#      assertions (shipped file surface, key parity, leaf-value sanity);
#   2. the files are additionally loaded into a FRESH I18n::Backend::Simple
#      instance, so acceptance criterion 1 ("I18n.t('decidim.contracts_sk.
#      contract.title') works") is verified through the real i18n translation
#      path without mutating global I18n state. The backend-translate form is
#      equivalent to I18n.t: I18n.t delegates to I18n.backend.translate.
# ---------------------------------------------------------------------------

require "spec_helper"

require "i18n"
require "rails_i18n/common_pluralizations/west_slavic"
require "yaml"

# Shared vocabulary and introspection for the example groups below. Kept in a
# plain module (not inside a describe block) so that its constants stay
# lint-clean and its helpers can be included where needed. Cop note: the
# module IS the pinned key/label vocabulary — its length grows with the
# engine's locale surface, not with logic, so the module budget is disabled
# rather than splitting the contract tables apart.
# rubocop:disable Metrics/ModuleLength
module LocaleContract
  # Repo-root-relative locale dir: this spec lives at spec/decidim/, so two
  # levels up is the engine root (config/locales sits beneath it).
  LOCALES_DIR = File.expand_path("../../config/locales", __dir__)
  LOCALES = %w[en sk].freeze

  # The acceptance-criterion key of civora-org/civora-platform#39.
  ACCEPTANCE_KEY = "decidim.contracts_sk.contract.title"

  # The admin content-field form labels per locale, per the data dictionary
  # (civora-org/civora-platform#75).
  CONTENT_FIELD_LABELS = {
    en: { subject_matter: "Subject matter", amount: "Amount", currency: "Currency",
          signed_on: "Signed on", effective_from: "Effective from", crz_url: "CRZ URL" },
    sk: { subject_matter: "Predmet zmluvy", amount: "Hodnota", currency: "Mena",
          signed_on: "Dátum podpisu", effective_from: "Dátum účinnosti", crz_url: "Odkaz na CRZ" }
  }.freeze

  # The admin party labels per locale, per the approved Slovak translations
  # (civora-org/civora-platform#76): object party = Objednávateľ,
  # contractor = Dodávateľ.
  PARTY_ROLE_LABELS = {
    en: { object: "Object party", contractor: "Contractor" },
    sk: { object: "Objednávateľ", contractor: "Dodávateľ" }
  }.freeze

  # The document kind labels per locale, per the approved translations
  # (civora-org/civora-platform#73). The admin (admin.documents.kinds.*)
  # and public (contract.document.*) vocabularies deliberately share the
  # same terminology.
  DOCUMENT_KIND_LABELS = {
    en: { contract: "Contract document", crz_export: "CRZ export", annex: "Annex", other: "Other document" },
    sk: { contract: "Zmluvný dokument", crz_export: "Export z CRZ", annex: "Príloha", other: "Iný dokument" }
  }.freeze

  # The lifecycle state labels per locale, in the contract_states.*
  # namespace reserved for them by docs/contract-lifecycle.md (first
  # consumed by the CRZ-handoff PDF, M02-05-C,
  # civora-org/civora-platform#74).
  CONTRACT_STATE_LABELS = {
    en: { draft: "Draft", in_review: "In review", returned: "Returned for changes",
          approved: "Approved", rejected: "Rejected", published: "Published",
          archived: "Archived" },
    sk: { draft: "Koncept", in_review: "V recenzii", returned: "Vrátená na doplnenie",
          approved: "Schválená", rejected: "Zamietnutá", published: "Zverejnená",
          archived: "Archivovaná" }
  }.freeze

  # The admin lifecycle transition-event button labels per locale (M02-06-A,
  # civora-org/civora-platform#66): the six events of
  # ContractLifecycle::TRANSITIONS. Slovak verb infinitives, symmetric with
  # the contract_states.* adjectives (Vrátiť -> Vrátená, Zamietnuť ->
  # Zamietnutá, ...).
  TRANSITION_EVENT_LABELS = {
    en: { submit: "Submit for review", return: "Return for changes",
          approve: "Approve", reject: "Reject", publish: "Publish",
          archive: "Archive" },
    sk: { submit: "Odoslať na kontrolu", return: "Vrátiť na doplnenie",
          approve: "Schváliť", reject: "Zamietnuť", publish: "Zverejniť",
          archive: "Archivovať" }
  }.freeze

  # The CRZ-handoff PDF's own labels per locale (M02-05-C,
  # civora-org/civora-platform#74). The PDF renders Slovak only; the en
  # values exist for key parity and documentation.
  CRZ_HANDOFF_PDF_LABELS = {
    en: { heading: "CRZ handoff aid",
          disclaimer: "This document is a handoff aid for the CRZ record — not a legal publication.",
          generated_on: "Generated on" },
    sk: { heading: "Pomôcka na odovzdanie do CRZ",
          disclaimer: "Tento dokument je pomôcka na odovzdanie do CRZ — nie právna publikácia.",
          generated_on: "Vygenerované" }
  }.freeze

  # The admin CRZ-handoff UI labels per locale (M02-05-C,
  # civora-org/civora-platform#74).
  CRZ_HANDOFF_ADMIN_LABELS = {
    en: { title: "CRZ handoff",
          disclaimer: "The generated PDF is a handoff aid for the CRZ record — not a legal publication.",
          document_title: "CRZ handoff export",
          download: "Download handoff PDF",
          generate: "Generate handoff PDF",
          replace: "Regenerate handoff PDF",
          download_missing: "The CRZ handoff PDF has not been generated yet." },
    sk: { title: "Odovzdanie do CRZ",
          disclaimer: "Vygenerovaný PDF je pomôcka na odovzdanie do CRZ — nie právna publikácia.",
          document_title: "Pomôcka na odovzdanie do CRZ",
          download: "Stiahnuť pomôcku (PDF)",
          generate: "Vygenerovať pomôcku (PDF)",
          replace: "Vygenerovať pomôcku znova (PDF)",
          download_missing: "Pomôcka na odovzdanie do CRZ ešte nebola vygenerovaná." }
  }.freeze

  # The public detail page's document section labels per locale
  # (civora-org/civora-platform#73).
  DOCUMENT_VIEW_LABELS = {
    en: {
      "contracts.show.documents" => "Documents",
      "contracts.show.documents_empty" => "No documents have been attached to this contract."
    },
    sk: {
      "contracts.show.documents" => "Dokumenty",
      "contracts.show.documents_empty" => "K tejto zmluve nie sú pripojené žiadne dokumenty."
    }
  }.freeze

  # The admin link-management labels per locale (M01-87,
  # civora-org/civora-platform#87). Target types are host-configured class
  # names (never localized) — the engine only localizes the chrome around
  # them.
  ADMIN_LINK_LABELS = {
    en: {
      "admin.links.index.title" => "Links",
      "admin.links.index.empty" => "No links have been added to this contract yet.",
      "admin.links.index.dangling" => "Target no longer available — remove this link or fix the target id.",
      "admin.links.create.success" => "Link added successfully.",
      "admin.links.create.error" => "Link could not be added.",
      "admin.links.destroy.link" => "Remove",
      "admin.links.destroy.confirm" => "Remove this link?",
      "admin.links.destroy.success" => "Link removed successfully.",
      "admin.links.destroy.error" => "Link could not be removed.",
      "admin.links.form.target_type" => "Target type",
      "admin.links.form.target_id" => "Target id",
      "admin.links.form.submit" => "Add link"
    },
    sk: {
      "admin.links.index.title" => "Odkazy",
      "admin.links.index.empty" => "K tejto zmluve neboli pridané žiadne odkazy.",
      "admin.links.index.dangling" => "Cieľ už nie je dostupný — odstráňte tento odkaz alebo opravte ID cieľa.",
      "admin.links.create.success" => "Odkaz bol úspešne pridaný.",
      "admin.links.create.error" => "Odkaz sa nepodarilo pridať.",
      "admin.links.destroy.link" => "Odstrániť",
      "admin.links.destroy.confirm" => "Odstrániť tento odkaz?",
      "admin.links.destroy.success" => "Odkaz bol úspešne odstránený.",
      "admin.links.destroy.error" => "Odkaz sa nepodarilo odstrániť.",
      "admin.links.form.target_type" => "Typ cieľa",
      "admin.links.form.target_id" => "ID cieľa",
      "admin.links.form.submit" => "Pridať odkaz"
    }
  }.freeze

  # The public detail page's link section heading per locale (M01-87,
  # civora-org/civora-platform#87) — the section is hidden entirely when
  # nothing renderable remains, so there is no empty-state key.
  LINK_VIEW_LABELS = {
    en: { "contracts.show.links" => "Links" },
    sk: { "contracts.show.links" => "Odkazy" }
  }.freeze

  # The public version-history labels per locale (M02-05-B,
  # civora-org/civora-platform#65, ADR-006): the current/historical
  # distinction is labelled, one heading per published version. The I18n
  # template token mirrors the shipped YAML value verbatim (cop off for
  # exactly that reason).
  # rubocop:disable Style/FormatStringToken
  VERSION_HISTORY_LABELS = {
    en: {
      "contracts.show.versions" => "Version history",
      "contracts.show.current_version" => "Current version",
      "contracts.show.version_label" => "Version %{version}",
      "contracts.show.versions_empty" => "No amendments have been published for this contract.",
      "contract.summary" => "Summary"
    },
    sk: {
      "contracts.show.versions" => "História verzií",
      "contracts.show.current_version" => "Aktuálna verzia",
      "contracts.show.version_label" => "Verzia %{version}",
      "contracts.show.versions_empty" => "K tejto zmluve nebola zverejnená žiadna zmena.",
      "contract.summary" => "Súhrn"
    }
  }.freeze
  # rubocop:enable Style/FormatStringToken

  # The admin amendment labels per locale (M02-05-B,
  # civora-org/civora-platform#65). The amendment state vocabulary
  # (draft/published) uses its own namespace — distinct from the
  # contract lifecycle's contract_states.*.
  ADMIN_AMENDMENT_LABELS = {
    en: {
      "admin.amendments.index.title" => "Amendments",
      "admin.amendments.states.draft" => "Draft",
      "admin.amendments.states.published" => "Published",
      "admin.amendments.form.version" => "Version",
      "admin.amendments.form.summary" => "Summary",
      "admin.amendments.form.state" => "State",
      "admin.amendments.publish.link" => "Publish"
    },
    sk: {
      "admin.amendments.index.title" => "Dodatky",
      "admin.amendments.states.draft" => "Koncept",
      "admin.amendments.states.published" => "Zverejnený",
      "admin.amendments.form.version" => "Verzia",
      "admin.amendments.form.summary" => "Súhrn",
      "admin.amendments.form.state" => "Stav",
      "admin.amendments.publish.link" => "Zverejniť"
    }
  }.freeze

  # The admin dashboard's pinned labels per locale (civora-org/civora-platform
  # #126): block titles (the role vocabulary of the page), the submitter
  # filter options and the shared chrome. Slovak carries diacritics.
  # rubocop:disable Style/FormatStringToken
  ADMIN_DASHBOARD_LABELS = {
    en: {
      "admin.dashboard.title" => "Overview",
      "admin.dashboard.blocks.review_queue.title" => "Waiting for my review",
      "admin.dashboard.blocks.returned.title" => "Returned to me",
      "admin.dashboard.blocks.approved.title" => "Approved, ready to publish",
      "admin.dashboard.blocks.overdue.title" => "CRZ deadline overdue",
      "admin.dashboard.show_all" => "Show all (%{count})",
      "admin.dashboard.counts.title" => "Contracts by state",
      "admin.dashboard.recent_activity.title" => "Recent activity",
      "admin.contracts.index.filters.submitters.any" => "Any submitter",
      "admin.contracts.index.filters.submitters.me" => "Submitted by me",
      "admin.contracts.index.filters.submitters.others" => "Submitted by others"
    },
    sk: {
      "admin.dashboard.title" => "Prehľad",
      "admin.dashboard.blocks.review_queue.title" => "Čakajú na moje posúdenie",
      "admin.dashboard.blocks.returned.title" => "Vrátené mne na úpravu",
      "admin.dashboard.blocks.approved.title" => "Schválené, pripravené na zverejnenie",
      "admin.dashboard.blocks.overdue.title" => "Lehota CRZ po termíne",
      "admin.dashboard.show_all" => "Zobraziť všetky (%{count})",
      "admin.dashboard.counts.title" => "Zmluvy podľa stavu",
      "admin.dashboard.recent_activity.title" => "Posledná aktivita",
      "admin.contracts.index.filters.submitters.any" => "Ľubovoľný odosielateľ",
      "admin.contracts.index.filters.submitters.me" => "Odoslané mnou",
      "admin.contracts.index.filters.submitters.others" => "Odoslané inými"
    }
  }.freeze
  # rubocop:enable Style/FormatStringToken

  # The admin audit-trail viewer labels per locale (civora-org/civora-platform
  # #92). The six lifecycle-event rows reuse the transition.* vocabulary
  # verbatim (pinned by TRANSITION_EVENT_LABELS — never a second vocabulary);
  # only the viewer's own chrome and the four non-transition action labels
  # carry keys of their own.
  # rubocop:disable Style/FormatStringToken
  ADMIN_AUDIT_LABELS = {
    en: {
      "admin.audit_events.index.title" => "Audit trail",
      "admin.audit_events.index.empty" => "No audit events have been recorded yet.",
      "admin.audit_events.index.headers.action" => "Action",
      "admin.audit_events.index.headers.record" => "Record",
      "admin.audit_events.index.headers.user" => "User",
      "admin.audit_events.index.headers.when" => "Date",
      "admin.audit_events.actions.redaction_confirmed" => "Redaction confirmed",
      "admin.audit_events.actions.amendment_publish" => "Amendment published",
      "admin.audit_events.actions.crz_import_create" => "Imported from CRZ",
      "admin.audit_events.actions.crz_import_update" => "Updated from CRZ",
      "admin.audit_events.amendment_target" => "Amendment v%{version}",
      "admin.audit_events.deleted_target" => "Record no longer exists",
      "admin.audit_events.filter_banner" => "Showing audit events for: %{title}",
      "admin.audit_events.back_to_all" => "Show all events",
      "admin.audit_events.unknown_actor" => "Unknown user"
    },
    sk: {
      "admin.audit_events.index.title" => "Auditná stopa",
      "admin.audit_events.index.empty" => "Zatiaľ nebola zaznamenaná žiadna udalosť auditnej stopy.",
      "admin.audit_events.index.headers.action" => "Akcia",
      "admin.audit_events.index.headers.record" => "Záznam",
      "admin.audit_events.index.headers.user" => "Používateľ",
      "admin.audit_events.index.headers.when" => "Dátum",
      "admin.audit_events.actions.redaction_confirmed" => "Skrytie údajov potvrdené",
      "admin.audit_events.actions.amendment_publish" => "Dodatok zverejnený",
      "admin.audit_events.actions.crz_import_create" => "Importované z CRZ",
      "admin.audit_events.actions.crz_import_update" => "Aktualizované z CRZ",
      "admin.audit_events.amendment_target" => "Dodatok č. %{version}",
      "admin.audit_events.deleted_target" => "Záznam už neexistuje",
      "admin.audit_events.filter_banner" => "Zobrazujú sa udalosti auditnej stopy pre: %{title}",
      "admin.audit_events.back_to_all" => "Zobraziť všetky udalosti",
      "admin.audit_events.unknown_actor" => "Neznámy používateľ"
    }
  }.freeze
  # rubocop:enable Style/FormatStringToken

  # The admin CRZ single-record import labels per locale (ADR-008,
  # civora-org/civora-platform#86). The outcome vocabulary mirrors the
  # CrzImport::Sync outcomes 1:1.
  # rubocop:disable Style/FormatStringToken
  CRZ_IMPORT_ADMIN_LABELS = {
    en: {
      "import_crz.label" => "CRZ contract id",
      "import_crz.submit" => "Import contract",
      "import_crz.submitting" => "Importing… the source is rate-limited; this can take up to a minute.",
      "import_crz.created" => "Contract %{source_id} imported and published.",
      "import_crz.collision" => "A manually created record already holds CRZ id %{source_id} — " \
                                "the import did not touch it. Resolve the collision manually."
    },
    sk: {
      "import_crz.label" => "ID zmluvy v CRZ",
      "import_crz.submit" => "Importovať zmluvu",
      "import_crz.submitting" => "Importujem… zdroj obmedzuje frekvenciu; môže to trvať až minútu.",
      "import_crz.created" => "Zmluva %{source_id} bola importovaná a zverejnená.",
      "import_crz.collision" => "Ručne vytvorený záznam už obsahuje ID z CRZ %{source_id} — " \
                                "import ho ponechal nedotknutý. Kolíziu je potrebné vyriešiť ručne."
    }
  }.freeze

  # The CRZ filing-confirmation labels per locale (civora-org/civora-platform
  # #125): the entry link, the lag-aware not-found wording and the public
  # "published in CRZ on" line (the date placeholder is part of the pin).
  CRZ_FILING_LABELS = {
    en: {
      "admin.contracts.crz_filing.link" => "Record CRZ filing",
      "admin.contracts.crz_filing.refusals.not_found" =>
        "No CRZ contract with id %{crz_id} was found. The data source may lag the CRZ by about a day — " \
        "try again later.",
      "contract.crz_filed_on" => "Published in CRZ on %{date}",
      "contract.crz_filed_confirmed" => "Publication in CRZ confirmed",
      "admin.audit_events.actions.crz_filed_override" => "CRZ filing confirmed despite differences"
    },
    sk: {
      "admin.contracts.crz_filing.link" => "Zaznamenať zverejnenie v CRZ",
      "admin.contracts.crz_filing.refusals.not_found" =>
        "Zmluva s ID %{crz_id} nebola v CRZ nájdená. Zdroj údajov môže za CRZ zaostávať približne o deň — " \
        "skúste to neskôr.",
      "contract.crz_filed_on" => "Zverejnené v CRZ dňa %{date}",
      "contract.crz_filed_confirmed" => "Zverejnenie v CRZ potvrdené",
      "admin.audit_events.actions.crz_filed_override" => "Zverejnenie v CRZ potvrdené napriek rozdielom"
    }
  }.freeze

  # The admin privacy-redaction confirmation labels per locale (ADR-007,
  # civora-org/civora-platform#91). The checklist items and the checkbox
  # affirmation are pinned verbatim — the confirmation's wording is the
  # gate's legal surface in both locales.
  ADMIN_REDACTION_LABELS = {
    en: {
      "admin.contracts.confirm_redaction.title" => "Privacy redaction",
      "admin.contracts.confirm_redaction.checklist.names_addresses" =>
        "personal names and addresses of natural persons",
      "admin.contracts.confirm_redaction.checklist.bank_details" => "bank and account details",
      "admin.contracts.confirm_redaction.checklist.amounts" =>
        "amounts tying the contract to identifiable persons",
      "admin.contracts.confirm_redaction.checklist.document_content" =>
        "sensitive content inside attached documents",
      "admin.contracts.confirm_redaction.checkbox_label" =>
        "I confirm that the required redactions have been made."
    },
    sk: {
      "admin.contracts.confirm_redaction.title" => "Skrytie osobných údajov",
      "admin.contracts.confirm_redaction.checklist.names_addresses" => "mená a adresy fyzických osôb",
      "admin.contracts.confirm_redaction.checklist.bank_details" => "bankové a účtové údaje",
      "admin.contracts.confirm_redaction.checklist.amounts" =>
        "sumy spájajúce zmluvu s identifikovateľnými osobami",
      "admin.contracts.confirm_redaction.checklist.document_content" =>
        "citlivý obsah v pripojených dokumentoch",
      "admin.contracts.confirm_redaction.checkbox_label" =>
        "Potvrdzujem, že požadované skrytie údajov bolo vykonané."
    }
  }.freeze

  # The navigation menu labels per locale (civora-org/civora-platform#86c):
  # the public catalogue entry (main + mobile menu) and the admin sidebar
  # entry carry separate keys so the host-facing vocabularies can diverge.
  MENU_LABELS = {
    en: { "menu.contracts" => "Contracts", "menu.admin_contracts" => "Contracts" },
    sk: { "menu.contracts" => "Zmluvy", "menu.admin_contracts" => "Zmluvy" }
  }.freeze

  # The admin index filter labels per locale (civora-org/civora-platform
  # #86b). The seven lifecycle states are NOT repeated here — the filter
  # options reuse the contract_states.* vocabulary verbatim (pinned by the
  # CONTRACT_STATE_LABELS table above); only the "any state" default option
  # carries its own key.
  ADMIN_INDEX_FILTER_LABELS = {
    en: {
      "admin.contracts.index.filters.state" => "State",
      "admin.contracts.index.filters.source" => "Source",
      "admin.contracts.index.filters.q" => "Search",
      "admin.contracts.index.filters.submit" => "Filter",
      "admin.contracts.index.filters.clear" => "Clear filters",
      "admin.contracts.index.filters.states.any" => "Any state",
      "admin.contracts.index.filters.sources.all" => "All sources",
      "admin.contracts.index.filters.sources.crz" => "CRZ import",
      "admin.contracts.index.filters.sources.editorial" => "Editorial"
    },
    sk: {
      "admin.contracts.index.filters.state" => "Stav",
      "admin.contracts.index.filters.source" => "Zdroj",
      "admin.contracts.index.filters.q" => "Hľadať",
      "admin.contracts.index.filters.submit" => "Filtrovať",
      "admin.contracts.index.filters.clear" => "Zrušiť filtre",
      "admin.contracts.index.filters.states.any" => "Ľubovolný stav",
      "admin.contracts.index.filters.sources.all" => "Všetky zdroje",
      "admin.contracts.index.filters.sources.crz" => "Import z CRZ",
      "admin.contracts.index.filters.sources.editorial" => "Redakčná"
    }
  }.freeze

  # The admin index per-state counters and the filtered no-matches labels
  # per locale (civora-org/civora-platform#93). The per-state chip labels
  # reuse the contract_states.* vocabulary verbatim (pinned by the
  # CONTRACT_STATE_LABELS table); only the "All" chip and the no-matches
  # block carry their own keys.
  ADMIN_INDEX_COUNTER_LABELS = {
    en: {
      "admin.contracts.index.counters.all" => "All",
      "admin.contracts.index.no_matches.heading" => "No contracts match the current filters.",
      "admin.contracts.index.no_matches.body" => "Adjust or clear the filters and try again.",
      "admin.contracts.index.no_matches.clear" => "Clear filters and show all contracts"
    },
    sk: {
      "admin.contracts.index.counters.all" => "Všetky",
      "admin.contracts.index.no_matches.heading" => "Žiadna zmluva nezodpovedá aktuálnym filtrom.",
      "admin.contracts.index.no_matches.body" => "Upravte alebo zrušte filtre a skúste to znova.",
      "admin.contracts.index.no_matches.clear" => "Zrušiť filtre a zobraziť všetky zmluvy"
    }
  }.freeze

  # The shared pagination labels per locale (civora-org/civora-platform
  # #86b) — one surface for the admin index and the public catalogue.
  PAGINATION_LABELS = {
    en: {
      "pagination.prev" => "Previous",
      "pagination.next" => "Next",
      "pagination.page_count" => "Page %{current} of %{total}",
      "pagination.aria_label" => "Pagination"
    },
    sk: {
      "pagination.prev" => "Predchádzajúca",
      "pagination.next" => "Ďalšia",
      "pagination.page_count" => "Strana %{current} z %{total}",
      "pagination.aria_label" => "Stránkovanie"
    }
  }.freeze

  # The public provenance labels for CRZ-mirrored records per locale
  # (civora-org/civora-platform#88, ADR-002 rule 1 + ADR-008 decisions
  # 4/6): the externally-confirmed badge, the mirror date line, the stale
  # notice and the preserved attribution paragraph (ekosystem terms:
  # "informatívny charakter, nie právne záväzné" — the wording is legal
  # surface, pinned verbatim in both locales).
  PROVENANCE_LABELS = {
    en: {
      "provenance.badge" => "Externally confirmed",
      "provenance.imported_on" => "Mirrored from the CRZ register on",
      "provenance.stale" => "This mirror may be out of date — verify the canonical record at crz.gov.sk.",
      "provenance.note" => "These fields mirror public metadata of the Slovak Central Register of Contracts (CRZ), " \
                           "obtained via ekosystem.slovensko.digital. They are externally confirmed information, not " \
                           "a legal publication; the canonical record lives at crz.gov.sk. Source data is provided " \
                           "for informational purposes only."
    },
    sk: {
      "provenance.badge" => "Externe potvrdené údaje",
      "provenance.imported_on" => "Zrkadlené z registra CRZ dňa",
      "provenance.stale" => "Toto zrkadlenie môže byť neaktuálne — overte pôvodný záznam na crz.gov.sk.",
      "provenance.note" => "Tieto polia zrkadlia verejné metadáta Slovenského centra zmluv (CRZ) získané cez " \
                           "ekosystem.slovensko.digital. Sú externe potvrdeným údajom, nie právnou publikáciou; " \
                           "autoritatívny záznam sa nachádza na crz.gov.sk. Zdrojové údaje majú len informatívny " \
                           "charakter."
    }
  }.freeze
  # rubocop:enable Style/FormatStringToken

  # The admin reviewer-decision labels per locale (civora-org/civora-platform
  # #90): the decision banner on the edit page (heading + timestamp line —
  # the banner's decision title reuses the contract_states.* vocabulary) and
  # the decision-reason input on the return/reject controls.
  # rubocop:disable Style/FormatStringToken
  ADMIN_REVIEW_DECISION_LABELS = {
    en: {
      "admin.contracts.review_decision.heading" => "Reviewer decision",
      "admin.contracts.review_decision.decided_on" => "Decided on %{reviewed_at}.",
      "admin.contracts.transition.review_reason.label" => "Decision reason",
      "admin.contracts.transition.review_reason.placeholder" =>
        "State the reason for this decision (required, up to 1000 characters)."
    },
    sk: {
      "admin.contracts.review_decision.heading" => "Rozhodnutie recenzenta",
      "admin.contracts.review_decision.decided_on" => "Rozhodnuté dňa %{reviewed_at}.",
      "admin.contracts.transition.review_reason.label" => "Dôvod rozhodnutia",
      "admin.contracts.transition.review_reason.placeholder" =>
        "Uveďte dôvod tohto rozhodnutia (povinný, najviac 1000 znakov)."
    }
  }.freeze
  # rubocop:enable Style/FormatStringToken

  # The four-eyes labels per locale (civora-org/civora-platform#123): the
  # self-review refusal flash and the audit-viewer labels of the
  # contract.<event>_self actions.
  FOUR_EYES_LABELS = {
    en: {
      "admin.contracts.transition.self_review" =>
        "You submitted this contract for review, so another reviewer must return, approve or reject it " \
        "(four-eyes rule).",
      "admin.audit_events.actions.return_self" => "Returned (self-review)",
      "admin.audit_events.actions.approve_self" => "Approved (self-review)",
      "admin.audit_events.actions.reject_self" => "Rejected (self-review)"
    },
    sk: {
      "admin.contracts.transition.self_review" =>
        "Túto zmluvu ste odoslali na posúdenie vy, preto ju musí vrátiť, schváliť alebo zamietnuť iný " \
        "posudzovateľ (pravidlo štyroch očí).",
      "admin.audit_events.actions.return_self" => "Vrátené (vlastné posúdenie)",
      "admin.audit_events.actions.approve_self" => "Schválené (vlastné posúdenie)",
      "admin.audit_events.actions.reject_self" => "Zamietnuté (vlastné posúdenie)"
    }
  }.freeze

  # The admin form hints and the engine-shipped date format per locale
  # (civora-org/civora-platform#79, #81). The date format is a strftime
  # STRING resolved by the engine's format_date helper — never a named I18n
  # format, so no host-app or rails-i18n locale data is ever required.
  FORM_HINT_AND_DATE_FORMAT_LABELS = {
    en: {
      "admin.contracts.form.amount_hint" =>
        "Use a dot as the decimal separator (e.g. 1250.50) — comma decimals are rejected.",
      "admin.parties.form.ico_hint" => "Leave blank or enter exactly 8 digits.",
      "date_formats.default" => "%Y-%m-%d",
      "date_formats.datetime" => "%Y-%m-%d %H:%M"
    },
    sk: {
      "admin.contracts.form.amount_hint" =>
        "Použite bodku ako oddeľovač desatinných miest (napr. 1250.50) — desatinná čiarka nie je prijateľná.",
      "admin.parties.form.ico_hint" => "Nechajte prázdne alebo zadajte presne 8 číslic.",
      "date_formats.default" => "%d. %m. %Y",
      "date_formats.datetime" => "%d. %m. %Y %H:%M"
    }
  }.freeze

  # The exact expected leaf-key surface under decidim.contracts_sk, including
  # the public catalogue keys (plan Option B of #39), the admin CRUD keys
  # (civora-org/civora-platform#58), the admin content-field form keys
  # (civora-org/civora-platform#75), the admin party keys
  # (civora-org/civora-platform#76), the public catalogue view keys
  # (civora-org/civora-platform#62, #63), the admin/public document keys
  # (civora-org/civora-platform#73), the CRZ-handoff keys (M02-05-C,
  # civora-org/civora-platform#74), the amendment/version-history keys
  # (M02-05-B, civora-org/civora-platform#65), the lifecycle
  # transition-event keys (M02-06-A, civora-org/civora-platform#66) and the
  # link-management keys (M01-87, civora-org/civora-platform#87) and the CRZ
  # deadline-tracking keys (civora-org/civora-platform#124). Sorted
  # alphabetically.
  EXPECTED_KEYS = [
    "admin.amendments.back_to_contract",
    "admin.amendments.create.error",
    "admin.amendments.create.success",
    "admin.amendments.destroy.confirm",
    "admin.amendments.destroy.error",
    "admin.amendments.destroy.link",
    "admin.amendments.destroy.success",
    "admin.amendments.edit.title",
    "admin.amendments.form.state",
    "admin.amendments.form.summary",
    "admin.amendments.form.version",
    "admin.amendments.index.empty",
    "admin.amendments.index.title",
    "admin.amendments.new.title",
    "admin.amendments.publish.confirm",
    "admin.amendments.publish.error",
    "admin.amendments.publish.link",
    "admin.amendments.publish.success",
    "admin.amendments.states.draft",
    "admin.amendments.states.published",
    "admin.amendments.update.error",
    "admin.amendments.update.success",
    "admin.audit_events.actions.amendment_publish",
    "admin.audit_events.actions.approve_self",
    "admin.audit_events.actions.crz_filed",
    "admin.audit_events.actions.crz_filed_override",
    "admin.audit_events.actions.crz_import_create",
    "admin.audit_events.actions.crz_import_update",
    "admin.audit_events.actions.crz_mirror_absorbed",
    "admin.audit_events.actions.redaction_confirmed",
    "admin.audit_events.actions.reject_self",
    "admin.audit_events.actions.return_self",
    "admin.audit_events.amendment_target",
    "admin.audit_events.back_to_all",
    "admin.audit_events.deleted_target",
    "admin.audit_events.filter_banner",
    "admin.audit_events.index.empty",
    "admin.audit_events.index.headers.action",
    "admin.audit_events.index.headers.record",
    "admin.audit_events.index.headers.user",
    "admin.audit_events.index.headers.when",
    "admin.audit_events.index.title",
    "admin.audit_events.unknown_actor",
    "admin.contracts.back_to_index",
    "admin.contracts.confirm_redaction.checkbox_label",
    "admin.contracts.confirm_redaction.checklist.amounts",
    "admin.contracts.confirm_redaction.checklist.bank_details",
    "admin.contracts.confirm_redaction.checklist.document_content",
    "admin.contracts.confirm_redaction.checklist.names_addresses",
    "admin.contracts.confirm_redaction.confirmed_on",
    "admin.contracts.confirm_redaction.description",
    "admin.contracts.confirm_redaction.invalid",
    "admin.contracts.confirm_redaction.submit",
    "admin.contracts.confirm_redaction.success",
    "admin.contracts.confirm_redaction.title",
    "admin.contracts.create.error",
    "admin.contracts.create.success",
    "admin.contracts.crz_filing.back",
    "admin.contracts.crz_filing.comparison.crz",
    "admin.contracts.crz_filing.comparison.editorial",
    "admin.contracts.crz_filing.comparison.field",
    "admin.contracts.crz_filing.comparison.fields.amount",
    "admin.contracts.crz_filing.comparison.fields.reference",
    "admin.contracts.crz_filing.comparison.fields.supplier_ico",
    "admin.contracts.crz_filing.comparison.official_record",
    "admin.contracts.crz_filing.comparison.published_on",
    "admin.contracts.crz_filing.comparison.published_on_unknown",
    "admin.contracts.crz_filing.comparison.result",
    "admin.contracts.crz_filing.comparison.statuses.match",
    "admin.contracts.crz_filing.comparison.statuses.mismatch",
    "admin.contracts.crz_filing.comparison.statuses.unverifiable",
    "admin.contracts.crz_filing.comparison.title",
    "admin.contracts.crz_filing.confirm",
    "admin.contracts.crz_filing.confirm_prompt",
    "admin.contracts.crz_filing.crz_id_label",
    "admin.contracts.crz_filing.description",
    "admin.contracts.crz_filing.filed",
    "admin.contracts.crz_filing.filed_override",
    "admin.contracts.crz_filing.invalid_id",
    "admin.contracts.crz_filing.lag_hint",
    "admin.contracts.crz_filing.link",
    "admin.contracts.crz_filing.lookup",
    "admin.contracts.crz_filing.override.label",
    "admin.contracts.crz_filing.override.placeholder",
    "admin.contracts.crz_filing.override.warning",
    "admin.contracts.crz_filing.refusals.already_filed",
    "admin.contracts.crz_filing.refusals.already_linked",
    "admin.contracts.crz_filing.refusals.failed",
    "admin.contracts.crz_filing.refusals.not_configured",
    "admin.contracts.crz_filing.refusals.not_fileable",
    "admin.contracts.crz_filing.refusals.not_found",
    "admin.contracts.crz_filing.refusals.out_of_scope",
    "admin.contracts.crz_filing.refusals.reason_rejected",
    "admin.contracts.crz_filing.refusals.reason_required",
    "admin.contracts.crz_filing.refusals.stale",
    "admin.contracts.crz_filing.refusals.withdrawn",
    "admin.contracts.crz_filing.title",
    "admin.contracts.deadline.badge.overdue",
    "admin.contracts.deadline.badge.today",
    "admin.contracts.deadline.badge.unknown",
    "admin.contracts.deadline.days.few",
    "admin.contracts.deadline.days.one",
    "admin.contracts.deadline.days.other",
    "admin.contracts.deadline.header.overdue",
    "admin.contracts.deadline.header.today",
    "admin.contracts.deadline.header.unknown",
    "admin.contracts.deadline.header.upcoming",
    "admin.contracts.deadline.hint",
    "admin.contracts.edit.title",
    "admin.contracts.form.amount",
    "admin.contracts.form.amount_hint",
    "admin.contracts.form.crz_url",
    "admin.contracts.form.currency",
    "admin.contracts.form.effective_from",
    "admin.contracts.form.reference",
    "admin.contracts.form.signed_on",
    "admin.contracts.form.subject_matter",
    "admin.contracts.form.title",
    "admin.contracts.import_crz.blank_id",
    "admin.contracts.import_crz.collision",
    "admin.contracts.import_crz.created",
    "admin.contracts.import_crz.description",
    "admin.contracts.import_crz.failed",
    "admin.contracts.import_crz.hint",
    "admin.contracts.import_crz.label",
    "admin.contracts.import_crz.lifecycle_guard",
    "admin.contracts.import_crz.linked",
    "admin.contracts.import_crz.not_configured",
    "admin.contracts.import_crz.not_found",
    "admin.contracts.import_crz.out_of_scope",
    "admin.contracts.import_crz.quarantined",
    "admin.contracts.import_crz.record_invalid",
    "admin.contracts.import_crz.submit",
    "admin.contracts.import_crz.submitting",
    "admin.contracts.import_crz.title",
    "admin.contracts.import_crz.unchanged",
    "admin.contracts.import_crz.updated",
    "admin.contracts.index.counters.all",
    "admin.contracts.index.counters.crz_due_soon",
    "admin.contracts.index.counters.crz_overdue",
    "admin.contracts.index.empty",
    "admin.contracts.index.filters.clear",
    "admin.contracts.index.filters.deadline",
    "admin.contracts.index.filters.deadlines.any",
    "admin.contracts.index.filters.deadlines.due_soon",
    "admin.contracts.index.filters.deadlines.overdue",
    "admin.contracts.index.filters.q",
    "admin.contracts.index.filters.source",
    "admin.contracts.index.filters.sources.all",
    "admin.contracts.index.filters.sources.crz",
    "admin.contracts.index.filters.sources.editorial",
    "admin.contracts.index.filters.state",
    "admin.contracts.index.filters.states.any",
    "admin.contracts.index.filters.submit",
    "admin.contracts.index.filters.submitter",
    "admin.contracts.index.filters.submitters.any",
    "admin.contracts.index.filters.submitters.me",
    "admin.contracts.index.filters.submitters.others",
    "admin.contracts.index.headers.crz_deadline",
    "admin.contracts.index.no_matches.body",
    "admin.contracts.index.no_matches.clear",
    "admin.contracts.index.no_matches.heading",
    "admin.contracts.index.title",
    "admin.contracts.new.title",
    "admin.contracts.review_decision.decided_on",
    "admin.contracts.review_decision.heading",
    "admin.contracts.transition.approve",
    "admin.contracts.transition.archive",
    "admin.contracts.transition.confirm.approve",
    "admin.contracts.transition.confirm.archive",
    "admin.contracts.transition.confirm.publish",
    "admin.contracts.transition.confirm.reject",
    "admin.contracts.transition.confirm.return",
    "admin.contracts.transition.confirm.submit",
    "admin.contracts.transition.invalid",
    "admin.contracts.transition.publish",
    "admin.contracts.transition.redaction_required",
    "admin.contracts.transition.reject",
    "admin.contracts.transition.return",
    "admin.contracts.transition.review_reason.label",
    "admin.contracts.transition.review_reason.placeholder",
    "admin.contracts.transition.review_reason_rejected",
    "admin.contracts.transition.review_reason_required",
    "admin.contracts.transition.self_review",
    "admin.contracts.transition.submit",
    "admin.contracts.transition.success",
    "admin.contracts.update.error",
    "admin.contracts.update.success",
    "admin.crz_handoff.create.error",
    "admin.crz_handoff.create.success",
    "admin.crz_handoff.disclaimer",
    "admin.crz_handoff.document_title",
    "admin.crz_handoff.download",
    "admin.crz_handoff.download_missing",
    "admin.crz_handoff.generate",
    "admin.crz_handoff.replace",
    "admin.crz_handoff.title",
    "admin.dashboard.all_contracts",
    "admin.dashboard.audit_trail",
    "admin.dashboard.blocks.approved.empty",
    "admin.dashboard.blocks.approved.hint",
    "admin.dashboard.blocks.approved.title",
    "admin.dashboard.blocks.due_soon.empty",
    "admin.dashboard.blocks.due_soon.hint",
    "admin.dashboard.blocks.due_soon.title",
    "admin.dashboard.blocks.overdue.empty",
    "admin.dashboard.blocks.overdue.hint",
    "admin.dashboard.blocks.overdue.title",
    "admin.dashboard.blocks.returned.empty",
    "admin.dashboard.blocks.returned.hint",
    "admin.dashboard.blocks.returned.title",
    "admin.dashboard.blocks.review_queue.empty",
    "admin.dashboard.blocks.review_queue.hint",
    "admin.dashboard.blocks.review_queue.hint_self_review",
    "admin.dashboard.blocks.review_queue.title",
    "admin.dashboard.columns.deadline",
    "admin.dashboard.columns.reason",
    "admin.dashboard.columns.redaction",
    "admin.dashboard.columns.reviewed",
    "admin.dashboard.columns.state",
    "admin.dashboard.columns.submitter",
    "admin.dashboard.columns.updated",
    "admin.dashboard.counts.all",
    "admin.dashboard.counts.empty",
    "admin.dashboard.counts.title",
    "admin.dashboard.overview_link",
    "admin.dashboard.recent_activity.empty",
    "admin.dashboard.recent_activity.show_all",
    "admin.dashboard.recent_activity.title",
    "admin.dashboard.redaction_missing",
    "admin.dashboard.show_all",
    "admin.dashboard.title",
    "admin.dashboard.unknown_submitter",
    "admin.documents.back_to_contract",
    "admin.documents.create.error",
    "admin.documents.create.success",
    "admin.documents.destroy.confirm",
    "admin.documents.destroy.error",
    "admin.documents.destroy.link",
    "admin.documents.destroy.success",
    "admin.documents.edit.title",
    "admin.documents.form.current_file",
    "admin.documents.form.file",
    "admin.documents.form.kind",
    "admin.documents.form.title",
    "admin.documents.index.empty",
    "admin.documents.index.title",
    "admin.documents.kinds.annex",
    "admin.documents.kinds.contract",
    "admin.documents.kinds.crz_export",
    "admin.documents.kinds.other",
    "admin.documents.new.title",
    "admin.documents.update.error",
    "admin.documents.update.success",
    "admin.links.create.error",
    "admin.links.create.success",
    "admin.links.destroy.confirm",
    "admin.links.destroy.error",
    "admin.links.destroy.link",
    "admin.links.destroy.success",
    "admin.links.form.submit",
    "admin.links.form.target_id",
    "admin.links.form.target_type",
    "admin.links.index.dangling",
    "admin.links.index.empty",
    "admin.links.index.title",
    "admin.parties.back_to_contract",
    "admin.parties.create.error",
    "admin.parties.create.success",
    "admin.parties.destroy.confirm",
    "admin.parties.destroy.error",
    "admin.parties.destroy.link",
    "admin.parties.destroy.success",
    "admin.parties.edit.title",
    "admin.parties.form.address",
    "admin.parties.form.ico",
    "admin.parties.form.ico_hint",
    "admin.parties.form.name",
    "admin.parties.form.role",
    "admin.parties.index.empty",
    "admin.parties.index.title",
    "admin.parties.new.title",
    "admin.parties.roles.contractor",
    "admin.parties.roles.object",
    "admin.parties.update.error",
    "admin.parties.update.success",
    "contract.amount",
    "contract.crz_filed",
    "contract.crz_filed_confirmed",
    "contract.crz_filed_on",
    "contract.crz_url",
    "contract.currency",
    "contract.document.annex",
    "contract.document.contract",
    "contract.document.crz_export",
    "contract.document.other",
    "contract.effective_from",
    "contract.party.contractor",
    "contract.party.object",
    "contract.published_on",
    "contract.published_on_crz",
    "contract.reference_number",
    "contract.signed_on",
    "contract.status",
    "contract.subject_matter",
    "contract.summary",
    "contract.title",
    "contract_states.approved",
    "contract_states.archived",
    "contract_states.draft",
    "contract_states.in_review",
    "contract_states.published",
    "contract_states.rejected",
    "contract_states.returned",
    "contracts.index.empty",
    "contracts.index.filters.active.amount_max",
    "contracts.index.filters.active.amount_min",
    "contracts.index.filters.active.party",
    "contracts.index.filters.active.published_from",
    "contracts.index.filters.active.published_to",
    "contracts.index.filters.active.q",
    "contracts.index.filters.active.signed_from",
    "contracts.index.filters.active.signed_to",
    "contracts.index.filters.active.sort",
    "contracts.index.filters.active.source",
    "contracts.index.filters.active_heading",
    "contracts.index.filters.amount",
    "contracts.index.filters.amount_max",
    "contracts.index.filters.amount_min",
    "contracts.index.filters.apply",
    "contracts.index.filters.clear",
    "contracts.index.filters.more",
    "contracts.index.filters.party",
    "contracts.index.filters.party_hint",
    "contracts.index.filters.published",
    "contracts.index.filters.published_from",
    "contracts.index.filters.published_to",
    "contracts.index.filters.signed",
    "contracts.index.filters.signed_from",
    "contracts.index.filters.signed_to",
    "contracts.index.filters.sort",
    "contracts.index.filters.sorts.amount_asc",
    "contracts.index.filters.sorts.amount_desc",
    "contracts.index.filters.sorts.published_asc",
    "contracts.index.filters.sorts.published_desc",
    "contracts.index.filters.source",
    "contracts.index.filters.sources.any",
    "contracts.index.filters.sources.crz",
    "contracts.index.filters.sources.editorial",
    "contracts.index.intro",
    "contracts.index.no_search_results",
    "contracts.index.open_data.atom",
    "contracts.index.open_data.crz_link",
    "contracts.index.open_data.crz_note",
    "contracts.index.open_data.csv",
    "contracts.index.open_data.csv_excel",
    "contracts.index.open_data.heading",
    "contracts.index.open_data.intro",
    "contracts.index.open_data.json",
    "contracts.index.open_data.own_only",
    "contracts.index.search_label",
    "contracts.index.search_submit",
    "contracts.index.title",
    "contracts.show.current_version",
    "contracts.show.documents",
    "contracts.show.documents_empty",
    "contracts.show.facts",
    "contracts.show.links",
    "contracts.show.parties",
    "contracts.show.parties_empty",
    "contracts.show.version_label",
    "contracts.show.versions",
    "contracts.show.versions_empty",
    "crz_handoff_pdf.disclaimer",
    "crz_handoff_pdf.generated_on",
    "crz_handoff_pdf.heading",
    "date_formats.datetime",
    "date_formats.default",
    "events.contract_approved.email_intro",
    "events.contract_approved.email_outro",
    "events.contract_approved.email_subject",
    "events.contract_approved.notification_title",
    "events.contract_published.email_intro",
    "events.contract_published.email_outro",
    "events.contract_published.email_subject",
    "events.contract_published.notification_title",
    "events.contract_rejected.email_intro",
    "events.contract_rejected.email_outro",
    "events.contract_rejected.email_subject",
    "events.contract_rejected.notification_title",
    "events.contract_returned.email_intro",
    "events.contract_returned.email_outro",
    "events.contract_returned.email_subject",
    "events.contract_returned.notification_title",
    "events.contract_submitted.email_intro",
    "events.contract_submitted.email_outro",
    "events.contract_submitted.email_subject",
    "events.contract_submitted.notification_title",
    "feeds.show.subtitle",
    "feeds.show.subtitle_filtered",
    "feeds.show.summary_signed",
    "feeds.show.title",
    "menu.admin_contracts",
    "menu.contracts",
    "meta.contract.amount",
    "meta.contract.reference",
    "meta.contract.supplier",
    "meta.contract.suppliers",
    "meta.contract.title",
    "meta.page",
    "meta.supplier.description",
    "meta.supplier.title",
    "pagination.aria_label",
    "pagination.next",
    "pagination.page_count",
    "pagination.prev",
    "provenance.badge",
    "provenance.imported_on",
    "provenance.note",
    "provenance.stale",
    "shared.switch.catalogue",
    "shared.switch.label",
    "shared.switch.statistics",
    "statistics.decimal_separator",
    "statistics.months.april",
    "statistics.months.august",
    "statistics.months.december",
    "statistics.months.february",
    "statistics.months.january",
    "statistics.months.july",
    "statistics.months.june",
    "statistics.months.march",
    "statistics.months.may",
    "statistics.months.november",
    "statistics.months.october",
    "statistics.months.september",
    "statistics.percent",
    "statistics.show.as_of",
    "statistics.show.catalogue_link",
    "statistics.show.contracts",
    "statistics.show.download_csv",
    "statistics.show.empty",
    "statistics.show.kpi.all_time",
    "statistics.show.kpi.own",
    "statistics.show.kpi.own_detail",
    "statistics.show.kpi.this_month",
    "statistics.show.kpi.this_year",
    "statistics.show.lead",
    "statistics.show.months.caption",
    "statistics.show.months.month",
    "statistics.show.months.so_far",
    "statistics.show.months.title",
    "statistics.show.months.unit",
    "statistics.show.next",
    "statistics.show.note",
    "statistics.show.provenance_html",
    "statistics.show.source",
    "statistics.show.sources.caption",
    "statistics.show.sources.crz",
    "statistics.show.sources.own",
    "statistics.show.sources.share",
    "statistics.show.sources.source",
    "statistics.show.sources.title",
    "statistics.show.sources.unit",
    "statistics.show.summary",
    "statistics.show.suppliers.by_count",
    "statistics.show.suppliers.by_value",
    "statistics.show.suppliers.by_value_in",
    "statistics.show.suppliers.rank",
    "statistics.show.suppliers.supplier",
    "statistics.show.suppliers.title",
    "statistics.show.suppliers.unit_count",
    "statistics.show.suppliers.unit_value",
    "statistics.show.table",
    "statistics.show.title",
    "statistics.show.value",
    "statistics.show.without_amount",
    "statistics.show.years.caption",
    "statistics.show.years.title",
    "statistics.show.years.unit",
    "statistics.show.years.unknown",
    "statistics.show.years.year",
    "suppliers.show.back",
    "suppliers.show.by_year",
    "suppliers.show.contracts",
    "suppliers.show.count",
    "suppliers.show.first_page",
    "suppliers.show.note",
    "suppliers.show.page_empty",
    "suppliers.show.summary",
    "suppliers.show.totals",
    "suppliers.show.year_unknown"
  ].freeze

  def locale_file(locale)
    File.join(LOCALES_DIR, "#{locale}.yml")
  end

  # Parsed YAML tree for a locale: { "en" => { "decidim" => { ... } } }.
  def translations(locale)
    YAML.safe_load(File.read(locale_file(locale)))
  end

  # The subtree under decidim.contracts_sk for a locale: the parsed tree is
  # { "<locale>" => { "decidim" => { "contracts_sk" => { ... } } } }.
  def module_tree(locale)
    translations(locale).fetch(locale).fetch("decidim").fetch("contracts_sk")
  end

  # Recursively collects sorted "a.b.c"-style leaf key paths of a subtree.
  def leaf_paths(subtree, prefix = [])
    subtree.each_with_object([]) do |(key, value), paths|
      path = prefix + [key]
      if value.is_a?(Hash)
        paths.concat(leaf_paths(value, path))
      else
        paths << path.join(".")
      end
    end.sort
  end

  # "locale: a.b.c" => leaf value, for every leaf of every shipped locale.
  def leaf_values
    LOCALES.each_with_object({}) do |locale, map|
      tree = module_tree(locale)
      leaf_paths(tree).each do |path|
        map["#{locale}: #{path}"] = path.split(".").reduce(tree, :fetch)
      end
    end
  end

  # Fresh backend per call - deterministic, no global I18n mutation.
  def fresh_backend
    backend = I18n::Backend::Simple.new
    backend.load_translations(*LOCALES.map { |locale| locale_file(locale) })
    backend
  end
end
# rubocop:enable Metrics/ModuleLength

# The public catalogue's own vocabulary (civora-org/civora-platform#62, #63),
# kept in its own module so that LocaleContract stays within its length
# budget and the public surface stays visually separate from the admin one.
# The public vocabulary pins grow with the catalogue's surface, not with logic.
# rubocop:disable Metrics/ModuleLength
module PublicCatalogueLabels
  # View labels per locale, keyed by their path under decidim.contracts_sk.
  VIEW_LABELS = {
    en: {
      "contract.published_on" => "Published on",
      "contract.published_on_crz" => "Published in CRZ on",
      "contracts.index.empty" => "No published contracts yet.",
      "contracts.index.no_search_results" => "No contracts match your search or filters.",
      "contracts.index.open_data.heading" => "Download data",
      "contracts.index.open_data.csv" => "CSV",
      "contracts.index.open_data.csv_excel" => "CSV for Excel",
      "contracts.index.open_data.json" => "JSON",
      "contracts.index.open_data.atom" => "Atom feed",
      "suppliers.show.count" => "Published contracts",
      "suppliers.show.totals" => "Total value",
      "suppliers.show.year_unknown" => "Signing date unknown",
      "suppliers.show.page_empty" => "There are no contracts on this page.",
      "statistics.show.title" => "Contract statistics",
      # rubocop:disable Style/FormatStringToken
      "statistics.show.as_of" => "Data as of %{time}",
      # rubocop:enable Style/FormatStringToken
      "statistics.months.october" => "October",
      # rubocop:disable Style/FormatStringToken
      "feeds.show.title" => "Contracts — %{organization}",
      "feeds.show.subtitle" => "Newly published contracts",
      "feeds.show.subtitle_filtered" => "Newly published contracts. Filters: %{filters}",
      "feeds.show.summary_signed" => "signed %{date}",
      # rubocop:enable Style/FormatStringToken
      "contracts.index.open_data.own_only" =>
        "Only the organisation's own records; records taken from CRZ are not included.",
      "contracts.index.open_data.crz_link" => "crz.gov.sk",
      "contracts.index.search_label" => "Search contracts",
      "contracts.index.search_submit" => "Search",
      "contracts.index.intro" => "Published contracts of the organisation, with their documents and change history.",
      "contracts.index.filters.active.amount_max" => "Amount to",
      "contracts.index.filters.active.amount_min" => "Amount from",
      "contracts.index.filters.active.party" => "Party",
      "contracts.index.filters.active.published_from" => "Published from",
      "contracts.index.filters.active.published_to" => "Published to",
      "contracts.index.filters.active.q" => "Search",
      "contracts.index.filters.active.signed_from" => "Signed from",
      "contracts.index.filters.active.signed_to" => "Signed to",
      "contracts.index.filters.active.sort" => "Sort",
      "contracts.index.filters.active.source" => "Source",
      "contracts.index.filters.active_heading" => "Active filters",
      "contracts.index.filters.amount" => "Amount (EUR)",
      "contracts.index.filters.amount_max" => "To",
      "contracts.index.filters.amount_min" => "From",
      "contracts.index.filters.apply" => "Apply filters",
      "contracts.index.filters.clear" => "Clear filters",
      "contracts.index.filters.more" => "More filters",
      "contracts.index.filters.party" => "Party",
      "contracts.index.filters.party_hint" => "Name or 8-digit IČO",
      "contracts.index.filters.published" => "Publication date",
      "contracts.index.filters.published_from" => "From",
      "contracts.index.filters.published_to" => "To",
      "contracts.index.filters.signed" => "Signing date",
      "contracts.index.filters.signed_from" => "From",
      "contracts.index.filters.signed_to" => "To",
      "contracts.index.filters.sort" => "Sort by",
      "contracts.index.filters.sorts.amount_asc" => "Lowest amount first",
      "contracts.index.filters.sorts.amount_desc" => "Highest amount first",
      "contracts.index.filters.sorts.published_asc" => "Oldest first",
      "contracts.index.filters.sorts.published_desc" => "Newest first",
      "contracts.index.filters.source" => "Source",
      "contracts.index.filters.sources.any" => "Any",
      "contracts.index.filters.sources.crz" => "Mirrored from CRZ",
      "contracts.index.filters.sources.editorial" => "Organisation's own records",
      "contracts.show.facts" => "Contract details",
      "contracts.show.parties" => "Parties",
      "contracts.show.parties_empty" => "No parties have been recorded for this contract."
    },
    sk: {
      "contract.published_on" => "Dátum zverejnenia",
      "contract.published_on_crz" => "Zverejnené v CRZ dňa",
      "contracts.index.empty" => "Zatiaľ nie je zverejnená žiadna zmluva.",
      "contracts.index.no_search_results" => "Žiadna zmluva nezodpovedá vášmu hľadaniu ani filtrom.",
      "contracts.index.open_data.heading" => "Stiahnuť dáta",
      "contracts.index.open_data.csv" => "CSV",
      "contracts.index.open_data.csv_excel" => "CSV pre Excel",
      "contracts.index.open_data.json" => "JSON",
      "contracts.index.open_data.atom" => "Atom kanál",
      "suppliers.show.count" => "Zverejnené zmluvy",
      "suppliers.show.totals" => "Celková hodnota",
      "suppliers.show.year_unknown" => "Dátum podpisu neznámy",
      "suppliers.show.page_empty" => "Na tejto stránke nie sú žiadne zmluvy.",
      "statistics.show.title" => "Štatistiky zmlúv",
      # rubocop:disable Style/FormatStringToken
      "statistics.show.as_of" => "Údaje k %{time}",
      # rubocop:enable Style/FormatStringToken
      "statistics.months.october" => "október",
      # rubocop:disable Style/FormatStringToken
      "feeds.show.title" => "Zmluvy — %{organization}",
      "feeds.show.subtitle" => "Novozverejnené zmluvy",
      "feeds.show.subtitle_filtered" => "Novozverejnené zmluvy. Filtre: %{filters}",
      "feeds.show.summary_signed" => "podpísaná %{date}",
      # rubocop:enable Style/FormatStringToken
      "contracts.index.open_data.own_only" =>
        "Len vlastné záznamy organizácie; záznamy prevzaté z CRZ nie sú zahrnuté.",
      "contracts.index.open_data.crz_link" => "crz.gov.sk",
      "contracts.index.search_label" => "Hľadať zmluvy",
      "contracts.index.search_submit" => "Hľadať",
      "contracts.index.intro" => "Zverejnené zmluvy organizácie s dokumentmi a históriou zmien.",
      "contracts.index.filters.active.amount_max" => "Suma do",
      "contracts.index.filters.active.amount_min" => "Suma od",
      "contracts.index.filters.active.party" => "Zmluvná strana",
      "contracts.index.filters.active.published_from" => "Zverejnené od",
      "contracts.index.filters.active.published_to" => "Zverejnené do",
      "contracts.index.filters.active.q" => "Hľadanie",
      "contracts.index.filters.active.signed_from" => "Podpísané od",
      "contracts.index.filters.active.signed_to" => "Podpísané do",
      "contracts.index.filters.active.sort" => "Zoradenie",
      "contracts.index.filters.active.source" => "Zdroj",
      "contracts.index.filters.active_heading" => "Aktívne filtre",
      "contracts.index.filters.amount" => "Suma (EUR)",
      "contracts.index.filters.amount_max" => "Do",
      "contracts.index.filters.amount_min" => "Od",
      "contracts.index.filters.apply" => "Použiť filtre",
      "contracts.index.filters.clear" => "Zrušiť filtre",
      "contracts.index.filters.more" => "Ďalšie filtre",
      "contracts.index.filters.party" => "Zmluvná strana",
      "contracts.index.filters.party_hint" => "Názov alebo 8-miestne IČO",
      "contracts.index.filters.published" => "Dátum zverejnenia",
      "contracts.index.filters.published_from" => "Od",
      "contracts.index.filters.published_to" => "Do",
      "contracts.index.filters.signed" => "Dátum podpisu",
      "contracts.index.filters.signed_from" => "Od",
      "contracts.index.filters.signed_to" => "Do",
      "contracts.index.filters.sort" => "Zoradiť podľa",
      "contracts.index.filters.sorts.amount_asc" => "Od najnižšej sumy",
      "contracts.index.filters.sorts.amount_desc" => "Od najvyššej sumy",
      "contracts.index.filters.sorts.published_asc" => "Od najstarších",
      "contracts.index.filters.sorts.published_desc" => "Od najnovších",
      "contracts.index.filters.source" => "Zdroj",
      "contracts.index.filters.sources.any" => "Všetky",
      "contracts.index.filters.sources.crz" => "Prevzaté z CRZ",
      "contracts.index.filters.sources.editorial" => "Vlastné záznamy organizácie",
      "contracts.show.facts" => "Údaje o zmluve",
      "contracts.show.parties" => "Zmluvné strany",
      "contracts.show.parties_empty" => "K tejto zmluve nie sú zaznamenané žiadne zmluvné strany."
    }
  }.freeze

  # The public detail page's party role labels: they reuse the terminology
  # fixed for the admin party management (#76) — object party =
  # Objednávateľ, contractor = Dodávateľ — never a second vocabulary.
  PARTY_ROLE_LABELS = {
    en: { object: "Object party", contractor: "Contractor" },
    sk: { object: "Objednávateľ", contractor: "Dodávateľ" }
  }.freeze
end
# rubocop:enable Metrics/ModuleLength

# The CRZ deadline-tracking vocabulary (civora-org/civora-platform#124),
# kept in its own module like the public catalogue's. The days keys are
# plurals (one/few/other): Slovak 2-4 take "dni" ("3 dni"), 5+ and 0 take
# "dní"; English carries few == other for key parity.
module CrzDeadlineLabels
  # rubocop:disable Style/FormatStringToken
  LABELS = {
    en: {
      "admin.contracts.deadline.badge.overdue" => "Overdue",
      "admin.contracts.deadline.badge.today" => "Due today",
      "admin.contracts.deadline.header.unknown" => "CRZ filing deadline unknown — add signing date",
      "admin.contracts.deadline.header.upcoming" => "CRZ filing deadline: %{date} (%{left} left)",
      "admin.contracts.index.headers.crz_deadline" => "CRZ deadline"
    },
    sk: {
      "admin.contracts.deadline.badge.overdue" => "Po termíne",
      "admin.contracts.deadline.badge.today" => "Dnes",
      "admin.contracts.deadline.header.unknown" =>
        "Lehota na zverejnenie v CRZ je neznáma — doplňte dátum podpisu",
      "admin.contracts.deadline.header.upcoming" =>
        "Lehota na zverejnenie v CRZ: %{date} (zostáva: %{left})",
      "admin.contracts.index.headers.crz_deadline" => "Lehota CRZ"
    }
  }.freeze
  # rubocop:enable Style/FormatStringToken

  # count => expected text, resolved through the Pluralization backend with
  # the rails-i18n West Slavic (cs/sk) rule.
  PLURALS = {
    en: { 1 => "1 day", 2 => "2 days", 7 => "7 days" },
    sk: { 1 => "1 deň", 2 => "2 dni", 3 => "3 dni", 4 => "4 dni", 5 => "5 dní", 7 => "7 dní", 21 => "21 dní" }
  }.freeze
end

RSpec.describe Decidim::ContractsSk do
  include LocaleContract

  describe "shipped file surface" do
    it "ships exactly the en and sk locale files" do
      expect(Dir.children(LocaleContract::LOCALES_DIR).sort).to eq(%w[en.yml sk.yml])
    end
  end

  describe "key surface (civora-org/civora-platform#39)" do
    it "declares exactly the expected decidim.contracts_sk keys in every locale" do
      LocaleContract::LOCALES.each do |locale|
        expect(leaf_paths(module_tree(locale))).to eq(LocaleContract::EXPECTED_KEYS), "locale: #{locale}"
      end
    end

    it "keeps en and sk in full key parity" do
      expect(leaf_paths(module_tree("sk"))).to eq(leaf_paths(module_tree("en")))
    end

    # Both regression guards deliberately walk the full vocabulary matrix
    # (every lifecycle event / every state key), so they exceed the
    # example-length budget by design — the same convention as the matrix
    # examples in contract_lifecycle_spec.rb.
    # rubocop:disable RSpec/ExampleLength
    it "labels every lifecycle transition event with a distinct sk value (civora-org/civora-platform#66)" do
      events = Decidim::ContractsSk::ContractLifecycle::TRANSITIONS.values.flat_map(&:keys).uniq.sort
      en_transition = module_tree("en").dig("admin", "contracts", "transition")
      sk_transition = module_tree("sk").dig("admin", "contracts", "transition")
      aggregate_failures do
        events.each do |event|
          key = event.to_s
          expect(en_transition).to have_key(key)
          expect(sk_transition).to have_key(key)
          expect(sk_transition.fetch(key)).not_to eq(en_transition.fetch(key))
        end
      end
    end

    it "translates every contract_states key into sk with a distinct value (civora-org/civora-platform#66)" do
      en_states = module_tree("en").fetch("contract_states")
      sk_states = module_tree("sk").fetch("contract_states")
      aggregate_failures do
        en_states.each_key do |key|
          expect(sk_states).to have_key(key)
          expect(sk_states.fetch(key)).not_to eq(en_states.fetch(key))
        end
      end
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe "leaf values" do
    it "maps every decidim.contracts_sk leaf to a String" do
      leaf_values.each_value { |value| expect(value).to be_a(String) }
    end

    it "maps no decidim.contracts_sk leaf to a blank string" do
      leaf_values.each_value { |value| expect(value).to match(/\S/) }
    end
  end

  describe "I18n resolution (acceptance criterion 1)" do
    let(:backend) { fresh_backend }

    it "translates decidim.contracts_sk.contract.title in en" do
      expect(backend.translate(:en, LocaleContract::ACCEPTANCE_KEY)).to eq("Contract")
    end

    it "translates decidim.contracts_sk.contract.title in sk" do
      expect(backend.translate(:sk, LocaleContract::ACCEPTANCE_KEY)).to eq("Zmluva")
    end

    it "translates the public catalogue titles in both locales" do
      aggregate_failures do
        expect(backend.translate(:en, "decidim.contracts_sk.contracts.index.title")).to eq("Contracts")
        expect(backend.translate(:sk, "decidim.contracts_sk.contracts.index.title")).to eq("Zmluvy")
      end
    end

    it "translates the admin content-field labels in both locales (civora-org/civora-platform#75)" do
      LocaleContract::CONTENT_FIELD_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.admin.contracts.form.#{key}")).to eq(value)
        end
      end
    end

    it "translates the admin party role labels in both locales (civora-org/civora-platform#76)" do
      LocaleContract::PARTY_ROLE_LABELS.each do |locale, labels|
        labels.each do |role, value|
          expect(backend.translate(locale, "decidim.contracts_sk.admin.parties.roles.#{role}")).to eq(value)
        end
      end
    end

    it "translates the admin document kind labels in both locales (civora-org/civora-platform#73)" do
      LocaleContract::DOCUMENT_KIND_LABELS.each do |locale, labels|
        labels.each do |kind, value|
          expect(backend.translate(locale, "decidim.contracts_sk.admin.documents.kinds.#{kind}")).to eq(value)
        end
      end
    end

    it "keeps the public document kind vocabulary identical to the admin one (civora-org/civora-platform#73)" do
      LocaleContract::DOCUMENT_KIND_LABELS.each do |locale, labels|
        labels.each do |kind, value|
          expect(backend.translate(locale, "decidim.contracts_sk.contract.document.#{kind}")).to eq(value)
        end
      end
    end

    it "translates the public detail page's document section labels in both locales (civora-org/civora-platform#73)" do
      LocaleContract::DOCUMENT_VIEW_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the CRZ filing-confirmation labels in both locales (civora-org/civora-platform#125)" do
      LocaleContract::CRZ_FILING_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the admin link-management labels in both locales (M01-87, civora-org/civora-platform#87)" do
      LocaleContract::ADMIN_LINK_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the public link section heading in both locales (M01-87, civora-org/civora-platform#87)" do
      LocaleContract::LINK_VIEW_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the lifecycle state labels in both locales (contract_states.*, M02-05-C)" do
      LocaleContract::CONTRACT_STATE_LABELS.each do |locale, labels|
        labels.each do |state, value|
          expect(backend.translate(locale, "decidim.contracts_sk.contract_states.#{state}")).to eq(value)
        end
      end
    end

    it "translates the lifecycle transition-event labels in both locales (M02-06-A, civora-org/civora-platform#66)" do
      LocaleContract::TRANSITION_EVENT_LABELS.each do |locale, labels|
        labels.each do |event, value|
          expect(backend.translate(locale, "decidim.contracts_sk.admin.contracts.transition.#{event}")).to eq(value)
        end
      end
    end

    it "translates the CRZ-handoff PDF labels in both locales (M02-05-C)" do
      LocaleContract::CRZ_HANDOFF_PDF_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.crz_handoff_pdf.#{key}")).to eq(value)
        end
      end
    end

    it "translates the admin CRZ-handoff UI labels in both locales (M02-05-C)" do
      LocaleContract::CRZ_HANDOFF_ADMIN_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.admin.crz_handoff.#{key}")).to eq(value)
        end
      end
    end

    it "translates the admin CRZ import labels in both locales (ADR-008, civora-org/civora-platform#86)" do
      LocaleContract::CRZ_IMPORT_ADMIN_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.admin.contracts.#{key}")).to eq(value)
        end
      end
    end

    it "translates the admin index filter labels in both locales (civora-org/civora-platform#86b)" do
      LocaleContract::ADMIN_INDEX_FILTER_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the admin index counter and no-matches labels in both locales (civora-org/civora-platform#93)" do
      LocaleContract::ADMIN_INDEX_COUNTER_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the admin privacy-redaction labels in both locales (ADR-007, civora-org/civora-platform#91)" do
      LocaleContract::ADMIN_REDACTION_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the admin reviewer-decision labels in both locales (civora-org/civora-platform#90)" do
      LocaleContract::ADMIN_REVIEW_DECISION_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the four-eyes labels in both locales (civora-org/civora-platform#123)" do
      LocaleContract::FOUR_EYES_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the CRZ deadline labels in both locales (civora-org/civora-platform#124)" do
      CrzDeadlineLabels::LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    # rubocop:disable RSpec/ExampleLength
    it "resolves the deadline day plurals with the Slovak one/few/other rule (civora-org/civora-platform#124)" do
      plural_backend = Class.new(I18n::Backend::Simple) { include I18n::Backend::Pluralization }.new
      plural_backend.load_translations(*LocaleContract::LOCALES.map { |locale| locale_file(locale) })
      plural_backend.store_translations(:sk, RailsI18n::Pluralization::WestSlavic.with_locale(:sk)[:sk])

      # The Pluralization module resolves the rule through the GLOBAL
      # I18n lookup, so the backend is swapped in for the example only.
      original_backend = I18n.backend
      I18n.backend = plural_backend
      begin
        CrzDeadlineLabels::PLURALS.each do |locale, expectations|
          expectations.each do |count, text|
            expect(I18n.t("decidim.contracts_sk.admin.contracts.deadline.days", locale: locale, count: count))
              .to eq(text)
          end
        end
      ensure
        I18n.backend = original_backend
      end
    end
    # rubocop:enable RSpec/ExampleLength

    it "translates the navigation menu labels in both locales (civora-org/civora-platform#86c)" do
      LocaleContract::MENU_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the pagination labels in both locales (civora-org/civora-platform#86b)" do
      LocaleContract::PAGINATION_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the provenance labels in both locales (civora-org/civora-platform#88)" do
      LocaleContract::PROVENANCE_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the public catalogue view labels in both locales (civora-org/civora-platform#62, #63)" do
      PublicCatalogueLabels::VIEW_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the public version-history labels in both locales (M02-05-B, civora-org/civora-platform#65)" do
      LocaleContract::VERSION_HISTORY_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the admin amendment labels in both locales (M02-05-B, civora-org/civora-platform#65)" do
      LocaleContract::ADMIN_AMENDMENT_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the admin audit-trail labels in both locales (civora-org/civora-platform#92)" do
      LocaleContract::ADMIN_AUDIT_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "translates the admin dashboard labels in both locales (civora-org/civora-platform#126)" do
      LocaleContract::ADMIN_DASHBOARD_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}", count: 7)).to eq(value.sub("%{count}", "7")) # rubocop:disable Style/FormatStringToken
        end
      end
    end

    it "translates the admin form hints and the engine date format in both locales (#79, #81)" do
      LocaleContract::FORM_HINT_AND_DATE_FORMAT_LABELS.each do |locale, labels|
        labels.each do |key, value|
          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
        end
      end
    end

    it "keeps the established Slovak party terminology on the public detail page (civora-org/civora-platform#63)" do
      PublicCatalogueLabels::PARTY_ROLE_LABELS.each do |locale, labels|
        labels.each do |role, value|
          expect(backend.translate(locale, "decidim.contracts_sk.contract.party.#{role}")).to eq(value)
        end
      end
    end
  end
end
