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
  # link-management keys (M01-87, civora-org/civora-platform#87). Sorted
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
    "admin.contracts.back_to_index",
    "admin.contracts.create.error",
    "admin.contracts.create.success",
    "admin.contracts.edit.title",
    "admin.contracts.form.amount",
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
    "admin.contracts.import_crz.not_found",
    "admin.contracts.import_crz.quarantined",
    "admin.contracts.import_crz.record_invalid",
    "admin.contracts.import_crz.submit",
    "admin.contracts.import_crz.submitting",
    "admin.contracts.import_crz.title",
    "admin.contracts.import_crz.unchanged",
    "admin.contracts.import_crz.updated",
    "admin.contracts.index.empty",
    "admin.contracts.index.filters.clear",
    "admin.contracts.index.filters.q",
    "admin.contracts.index.filters.source",
    "admin.contracts.index.filters.sources.all",
    "admin.contracts.index.filters.sources.crz",
    "admin.contracts.index.filters.sources.editorial",
    "admin.contracts.index.filters.state",
    "admin.contracts.index.filters.states.any",
    "admin.contracts.index.filters.submit",
    "admin.contracts.index.title",
    "admin.contracts.new.title",
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
    "admin.contracts.transition.reject",
    "admin.contracts.transition.return",
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
    "contracts.index.no_search_results",
    "contracts.index.search_label",
    "contracts.index.search_submit",
    "contracts.index.title",
    "contracts.show.current_version",
    "contracts.show.documents",
    "contracts.show.documents_empty",
    "contracts.show.links",
    "contracts.show.parties",
    "contracts.show.parties_empty",
    "contracts.show.version_label",
    "contracts.show.versions",
    "contracts.show.versions_empty",
    "crz_handoff_pdf.disclaimer",
    "crz_handoff_pdf.generated_on",
    "crz_handoff_pdf.heading",
    "menu.admin_contracts",
    "menu.contracts",
    "pagination.aria_label",
    "pagination.next",
    "pagination.page_count",
    "pagination.prev",
    "provenance.badge",
    "provenance.imported_on",
    "provenance.note",
    "provenance.stale"
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
module PublicCatalogueLabels
  # View labels per locale, keyed by their path under decidim.contracts_sk.
  VIEW_LABELS = {
    en: {
      "contract.published_on" => "Published on",
      "contracts.index.empty" => "No published contracts yet.",
      "contracts.index.no_search_results" => "No contracts match your search.",
      "contracts.index.search_label" => "Search contracts",
      "contracts.index.search_submit" => "Search",
      "contracts.show.parties" => "Parties",
      "contracts.show.parties_empty" => "No parties have been recorded for this contract."
    },
    sk: {
      "contract.published_on" => "Dátum zverejnenia",
      "contracts.index.empty" => "Zatiaľ nie je zverejnená žiadna zmluva.",
      "contracts.index.no_search_results" => "Žiadna zmluva nezodpovedá vášmu hľadaniu.",
      "contracts.index.search_label" => "Hľadať zmluvy",
      "contracts.index.search_submit" => "Hľadať",
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

    it "keeps the established Slovak party terminology on the public detail page (civora-org/civora-platform#63)" do
      PublicCatalogueLabels::PARTY_ROLE_LABELS.each do |locale, labels|
        labels.each do |role, value|
          expect(backend.translate(locale, "decidim.contracts_sk.contract.party.#{role}")).to eq(value)
        end
      end
    end
  end
end
