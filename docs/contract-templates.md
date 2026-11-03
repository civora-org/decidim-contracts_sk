# Contract templates: schema and host requirements

Steps P1 and P5 of [civora-org/civora-platform#211](https://github.com/civora-org/civora-platform/issues/211). P1 shipped the schema and the models; P5 (the last section of this page) adds "new contract from a template" in the admin, the generation command and the import task. Template upload and editing screens, and the redaction-confirmation integration, come in later steps (see the issue). Toolchain findings: [spikes/contract-templates-toolchain.md](spikes/contract-templates-toolchain.md).

## Tables

All tables are prefixed `decidim_contracts_sk_` and tenant-scoped, either by `decidim_organization_id` or through their parent contract.

| Table | Model | Purpose |
|-------|-------|---------|
| `contract_templates` | `ContractTemplate` | One version of a template lineage (organization, `lineage_key`, `version`) with its Word file (`has_one_attached :file`). |
| `contract_template_fields` | `ContractTemplateField` | The merge fields of a version: key, label, type, position, required, personal flag. |
| `contract_organization_profiles` | `ContractOrganizationProfile` | The town's contract header, one row per organization, as an allowlisted JSON. |
| `contract_template_entries` | `ContractTemplateEntry` | What an editor entered for one contract (one entry per contract). |
| `generated_documents` | `GeneratedDocument` | Files generated from an entry. Admin-only; separate from the public `Document`. |
| `reference_counters` | `ReferenceCounter` | Per-organization sequences for internal contract numbers. |

Rules worth knowing:

- **A used version is immutable.** Once any entry references a template version, its attributes (except `status`), its fields and its attached file cannot change, and it cannot be deleted. Change a template by creating the next version.
- **Personal data is split.** Values of personal-data fields live only in `personal_values`, which is encrypted at rest. Everything else lives in `values` (plain JSON). The entry validation refuses a personal field's value in `values`.
- **The organization header is an allowlist.** Allowed keys: `official_name`, `seat`, `ico`, `dic`, `bank_name`, `iban`, `bic`, `statutory_name`, `statutory_title`, `signing_place`. Unknown keys are rejected. The IČO must be 8 digits; the IBAN is checked loosely (shape only, no check digits).
- **Counters are race-safe.** `ReferenceCounter.next!(organization, scope_key)` creates the row on first use and increments it under a row lock. Use `ReferenceCounter.scope_key_for("zmluvy", 2026)` for a yearly sequence.

## Host requirements: Active Record Encryption

`ContractTemplateEntry#personal_values` uses Active Record Encryption (`encrypts`, non-deterministic). Decidim does not configure it, and neither does this engine. **The host must set two secrets**, otherwise the first read or write of a non-empty `personal_values` raises `ActiveRecord::Encryption::Errors::Configuration` (it fails loudly; it never stores plaintext):

```ruby
# config/application.rb (or an initializer), values from the secret store, never committed
config.active_record.encryption.primary_key         = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY")
config.active_record.encryption.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT")
```

Equivalent: `active_record_encryption.primary_key` and `active_record_encryption.key_derivation_salt` in the Rails credentials. Generate values with `bin/rails db:encryption:init`. `deterministic_key` is not needed.

Operational consequences:

- These secrets are as critical as `SECRET_KEY_BASE`: losing them makes every stored `personal_values` unreadable. Back them up with the other secrets, separately from database backups.
- Do not rotate by replacing the primary key. To rotate, add the old key to `config.active_record.encryption.previous` (a list of key-and-salt entries) and re-save the records.
- The engine adds `personal_values`, the whole `entry.values.*` subtree and `entry.title` (the contract-template form's parameters) to `config.filter_parameters`, and Active Record already filters `personal_values` from `inspect`. The host's own log and error-reporting setup should not be loosened, and must apply `filter_parameters` to anything that records request parameters.

The engine's specs use fixed, public test keys set in `spec/dummy/config/application.rb`. They exist only for deterministic tests and must never be reused in a real host.

## Migrations

Six additive, reversible creates, dated 2026-10-20 (never in the future; see `migration_timestamps_spec.rb`). Hosts copy them verbatim with their original timestamps (README: "Upgrading the engine"), after the engine's earlier migrations. They need no backfill and touch no existing table. The host already owns the ActiveStorage tables the file attachments use.

## New contract from a template (step P5)

Editors fill a form once; the engine creates a draft contract, stores what was typed, and generates four files: the internal Word and PDF, and the publication Word and PDF with every personal value replaced by a fixed block. The draft then goes through the normal workflow (four-eyes review, redaction confirmation).

### Where it is

| Page | Route | Who |
|------|-------|-----|
| Choose a template | `GET /admin/contract_templates` | editor (the contract `:create` permission) |
| The form | `GET /admin/contract_templates/:id/entry/new`, `POST .../entry` | editor |
| Edit values and generate again | `GET /admin/contracts/:id/template_entry/edit`, `PATCH .../template_entry` | editor, contract still editable (`:update`) |
| Download | `GET /admin/contracts/:id/generated_documents/:doc_id` | any engine role holder |

The contracts list has a "Nová zmluva zo šablóny" button when the organization has an active template. The contract page shows the internal number, the downloads (internal Word, internal PDF, publication PDF; the publication Word is an intermediate and is not offered) and, for an editor, "generate again". Generated files are never linked from, or served by, any public route (`spec/requests/admin/contracts_from_contract_template_spec.rb` pins this).

### What a template author names

A merge field is `MERGEFIELD =name` (see the services page). The name decides how the engine treats it:

| Name | Treatment |
|------|-----------|
| `cislo_zmluvy`, `interne_cislo`, `internal_number` | the internal number, never typed |
| `org_nazov`, `org_sidlo`, `org_adresa`, `org_ico`, `org_dic`, `org_iban`, `org_banka`, `org_bic`, `org_statutar`, `org_statutar_funkcia`, `org_miesto_podpisu` (or `org_<header key>`) | filled from the organization profile; the field must have type `org_header` |
| `<money field>_slovom`, `<money field>_words` | the amount in words (`AmountInWords`), never typed. Paired with the money field of the same base name, else the only money field of the template |
| anything else | asked for in the form, by its type |

The contract's own amount and signing date come from the first money field named `suma_celkom`, `cena_celkom`, `celkova_cena`, `suma`, `cena` or `kupna_cena`, and the first date field named `datum_podpisu`, `datum_uzavretia`, `datum_zmluvy` or `signed_on`.

Field types and input (stored in one canonical form, shown the Slovak way): `text` and `person` (255 characters), `long_text` (5000), `date` (`1. 1. 2026`, `1.1.2026`, `2026-01-01`), `money` (`3 062,50`, `3.062,50`, `3062.5`; two decimals, non-negative, up to 9 999 999 999,99; an ambiguous `3.062` is refused), `number` (decimal comma). `person` fields, and any field flagged `personal_data`, are stored only in the encrypted `personal_values` and are hidden in the publication copy. Group headings come from `group_key` (`decidim.contracts_sk.admin.template_entries.groups.<key>`, else the humanized key).

### The internal number

`ReferenceCounter` scope `zmluvy:<year>`, per organization, formatted with the template's `reference_pattern` (`{N}` and `{YYYY}`; default `{N}/{YYYY}`). A new contract's `reference` is the internal number. Regenerating reuses the number.

### What generating does

`Admin::GenerateFromTemplate`, in one transaction (a failure rolls back everything, including the number taken from the counter):

1. a new contract through `CreateContract` (author = the editor, state draft), or, with a contract given, `with_lock` plus an in-lock `editable?` re-check;
2. the header from `ContractOrganizationProfile` (a missing header value stops the generation with a message naming it);
3. `DocumentGenerator` (fill, sanitize, convert, redaction verification);
4. the `ContractTemplateEntry` (non-personal values in `values`, personal ones encrypted), the four `GeneratedDocument` rows with their files (SHA-256 checksum recorded), the previous current ones marked `superseded` (their files are kept);
5. on regeneration, `redaction_confirmed_at` is cleared: the documents changed, so a human confirms again;
6. the audit event `contract.generated_from_template` (actor, contract, time; never a value).

`RedactionFailed` or a converter failure stores nothing and the editor sees a message; a leak means the template does not mark every personal value as personal. The request is synchronous (about a second with LibreOffice) and holds a transaction while the converter runs.

Pages that hold typed values (the form, the edit form, the downloads) send `Cache-Control: no-store`. Request parameters are filtered (every typed value and the title) from the request log through `config.filter_parameters`; flashes and the audit trail carry no values either. If the encryption keys are missing, generating stops with a message and stores nothing (no value in the message).

**Locks and timeouts.** Generation runs inside one transaction. The converter timeout is 60 seconds (`LibreOfficeCli`), and for that time the new contract's numbering row (`ReferenceCounter`, per organization and year) is locked, and so is the contract row when regenerating. A second generation in the same organization waits for it, so a host with a PostgreSQL `lock_timeout` or `statement_timeout` below about 65 seconds can fail the waiting request with an error page (nothing is stored; the editor retries). Numbers whose reference already exists in the organization (a hand-entered `1/2026`) are skipped and the counter moves past them.

### Loading a template by hand

```bash
bin/rails "decidim_contracts_sk:templates:import[<org_id>,<path/to/file.docx>,<lineage_key>,<Template name>]"
```

The file must be fields-ready (see the services page): it is linted (any error refuses it), control fields (`x:if`, `x:each`) are refused because the form cannot fill them yet, and the sanitized copy is stored. Field types are guessed from the names (`datum_*`/`*_datum` date, `cena_*`/`suma_*`/`*_cena`/`*_suma` money, `org_*` header, everything else text). An optional sidecar `<path>.fields.yml` refines it; unknown keys are an error:

```yaml
person: [kupujuci_meno, kupujuci_rc]   # personal data, hidden in the publication copy
required: [predmet, suma_celkom]       # or: required: all
types: { vymera: number }
labels: { kupujuci_meno: "Kupujúci - meno" }
groups: { kupujuci_meno: kupujuci }
```

A second import with the same `lineage_key` creates version 2, activates it and archives the older active version. Existing contracts stay on the version they were written with.

### Before the first use on a host

The host needs the Active Record Encryption keys (above), LibreOffice in the image (or its own `pdf_converter`), and a `ContractOrganizationProfile` row for the organization with the header values the templates use (there is no screen for it yet; create it in a console).
