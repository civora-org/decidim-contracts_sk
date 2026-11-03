# Contract templates: schema and host requirements

Steps P1 and P5 of [civora-org/civora-platform#211](https://github.com/civora-org/civora-platform/issues/211). P1 shipped the schema and the models; P5 (the last section of this page) adds "new contract from a template" in the admin, the generation command and the import task. P6 adds the municipality header screen, group headings, the redaction-confirmation integration and the per-role permissions (see the last sections). A template upload screen comes in a later step (see the issue). Toolchain findings: [spikes/contract-templates-toolchain.md](spikes/contract-templates-toolchain.md).

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

Six additive, reversible creates, dated 2026-10-20 (never in the future; see `migration_timestamps_spec.rb`). Hosts copy them verbatim with their original timestamps (README: "Upgrading the engine"), after the engine's earlier migrations. They need no backfill and touch no existing table. Step P6 adds one more, `20261103000001_add_group_label_to_decidim_contracts_sk_contract_template_fields`: a nullable string column `group_label` on `contract_template_fields` (reversible, no default, no backfill, no index). Hosts copy it verbatim with its timestamp. The host already owns the ActiveStorage tables the file attachments use.

## New contract from a template (step P5)

Editors fill a form once; the engine creates a draft contract, stores what was typed, and generates four files: the internal Word and PDF, and the publication Word and PDF with every personal value replaced by a fixed block. The draft then goes through the normal workflow (four-eyes review, redaction confirmation).

### Where it is

| Page | Route | Who |
|------|-------|-----|
| Choose a template | `GET /admin/contract_templates` | editor (the contract `:create` permission) |
| The form | `GET /admin/contract_templates/:id/entry/new`, `POST .../entry` | editor |
| Edit values and generate again | `GET /admin/contracts/:id/template_entry/edit`, `PATCH .../template_entry` | editor, contract still editable (`:update`) |
| Download | `GET /admin/contracts/:id/generated_documents/:doc_id` | internal copy: editor; publication PDF: any engine role holder |

The contracts list has a "Nová zmluva zo šablóny" button when the organization has an active template. The contract page shows the internal number, the downloads the signed-in role may open (an editor sees internal Word, internal PDF and publication PDF; a reviewer sees only the publication PDF; the publication Word is an intermediate and is never offered) and, for an editor, "generate again". Generated files are never linked from, or served by, any public route (`spec/requests/admin/contracts_from_contract_template_spec.rb` pins this).

### What a template author names

A merge field is `MERGEFIELD =name` (see the services page). The name decides how the engine treats it:

| Name | Treatment |
|------|-----------|
| `cislo_zmluvy`, `interne_cislo`, `internal_number` | the internal number, never typed |
| `org_nazov`, `org_sidlo`, `org_adresa`, `org_ico`, `org_dic`, `org_iban`, `org_banka`, `org_bic`, `org_statutar`, `org_statutar_funkcia`, `org_miesto_podpisu` (or `org_<header key>`) | filled from the organization profile; the field must have type `org_header` |
| `<money field>_slovom`, `<money field>_words` | the amount in words (`AmountInWords`), never typed. Paired with the money field of the same base name, else the only money field of the template |
| anything else | asked for in the form, by its type |

The contract's own amount and signing date come from the first money field named `suma_celkom`, `cena_celkom`, `celkova_cena`, `suma`, `cena` or `kupna_cena`, and the first date field named `datum_podpisu`, `datum_uzavretia`, `datum_zmluvy` or `signed_on`.

Field types and input (stored in one canonical form, shown the Slovak way): `text` and `person` (255 characters), `long_text` (5000), `date` (`1. 1. 2026`, `1.1.2026`, `2026-01-01`), `money` (`3 062,50`, `3.062,50`, `3062.5`; two decimals, non-negative, up to 9 999 999 999,99; an ambiguous `3.062` is refused), `number` (decimal comma). `person` fields, and any field flagged `personal_data`, are stored only in the encrypted `personal_values` and are hidden in the publication copy. A field's caption is its `label`. Group headings come from the `group_label` stored on the group's fields (set by the import), else from `group_key` through the locale map (`decidim.contracts_sk.admin.template_entries.groups.<key>`), else the humanized key.

### The internal number

`ReferenceCounter` scope `zmluvy:<year>`, per organization, formatted with the template's `reference_pattern` (`{N}` and `{YYYY}`; default `{N}/{YYYY}`). A new contract's `reference` is the internal number. Regenerating reuses the number.

### What generating does

`Admin::GenerateFromTemplate`, in one transaction (a failure rolls back everything, including the number taken from the counter):

1. a new contract through `CreateContract` (author = the editor, state draft), or, with a contract given, `with_lock` plus an in-lock `editable?` re-check;
2. the header from `ContractOrganizationProfile` (a missing header value stops the generation with a message naming it; the form then links to the header screen for an organization admin);
3. `DocumentGenerator` (fill, sanitize, convert, redaction verification);
4. the `ContractTemplateEntry` (non-personal values in `values`, personal ones encrypted), the four `GeneratedDocument` rows with their files (SHA-256 checksum recorded), the previous current ones marked `superseded` (their files are kept);
5. the parties of the contract (section "Parties of a contract from a template");
6. on regeneration, `redaction_confirmed_at` is cleared and the publication copy promoted by an earlier confirmation is removed from the contract's documents: the documents changed, so a human confirms again;
7. the audit event `contract.generated_from_template` (actor, contract, time; never a value).

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
group_labels: { kupujuci: "Kupujúci" }   # heading of each group, diacritics allowed
reference_pattern: "{N}/{YYYY} Odd.X"    # internal number pattern; "" = back to the default
```

A second import with the same `lineage_key` creates version 2, activates it and archives the older active version. Existing contracts stay on the version they were written with.

**What a re-import keeps.** Settings stored on the template row rather than in the Word file or the sidecar are carried over from the latest earlier version of the lineage (any status): today that is `reference_pattern`. The sidecar's `reference_pattern` wins when present (an empty value clears it). The task prints `carried over from v1: reference_pattern=...` (or `nothing to carry`), so a changed numbering is never silent. Field definitions (types, labels, groups, person, required, counterparty) are not inherited: they come from the Word file and the sidecar on every import, so keep the sidecar next to the file. The number sequence is not per version: `ReferenceCounter` is keyed per organization and year (`zmluvy:<year>`), so numbering continues across versions and across templates.

### Before the first use on a host

The host needs the Active Record Encryption keys (above), LibreOffice in the image (or its own `pdf_converter`), and the municipality header filled in on **Hlavička obce** (next section).

## The municipality header screen (step P6)

`/admin/organization_profile` (sidebar item **Hlavička obce**, shown to organization admins only) is where the header the templates draw their `org_*` fields from is entered: official name, seat, IČO, DIČ, bank, IBAN, BIC, statutory representative and function, place of signing. It is the allowlist from `ContractOrganizationProfile::HEADER_KEYS`; unknown keys are not accepted. Blank fields are not stored. The IČO must be eight digits and the IBAN must have the shape of one (check digits are not verified).

- **Who:** an organization admin who has accepted the admin terms (the same rule as role administration). Editors and reviewers never see the screen; the generation form shows them the header read-only, and when a value is missing it tells them to ask an administrator. For an organization admin the same hint links to the screen.
- **What changes:** a change applies to documents generated from then on. Documents already generated are not rewritten; regenerate a contract to pick up a new header.
- **Audit:** every save writes one audit row per header key whose value changed (`organization_profile.changed.<key>`), and removing the header writes `organization_profile.removed`. The rows hold the actor, the time and the key. Neither the old nor the new value is ever recorded.
- **Removing the header** makes generation stop with "missing header value" until it is filled in again.

## Field labels and group headings (step P6)

The caption of a field was already stored (`contract_template_fields.label`, required, filled from the sidecar's `labels` or a humanized key). P6 adds the missing half: `contract_template_fields.group_label`, a nullable string holding the heading of the field's group. Without it a group's heading came only from a locale file keyed by the ASCII `group_key`, so a town could not get "Kupujúci" with its diacritics without a code change. The import writes the heading onto every field of the group from the sidecar's `group_labels`; the form uses it first and falls back as described above, so templates imported earlier look exactly as before. It is a plain string, not a translated column: the engine has no translated columns and a template is written in one language.

## Publication copy and the redaction confirmation (step P6)

When an editor confirms the redaction of a contract that has a **current** generated publication PDF, `ConfirmRedaction` promotes that file to the contract's publishable document in the same locked transaction as the stamp: a `Document` of kind `contract` (the same record a manual upload creates and the public page lists once the contract is published), linked from the generated row (`promoted_document_id`). One extra audit row, `contract.publication_copy_promoted`, records it.

- **Only the current copy.** Regenerating supersedes the old rows, clears `redaction_confirmed_at` and removes the Document the old copy had promoted, all under the contract's row lock, which the confirmation also takes. A superseded copy therefore can never be promoted, and a file whose SHA-256 no longer matches the recorded checksum is refused (the confirmation fails and nothing is stamped).
- **Manual uploads are untouched.** A contract without a generated copy is confirmed exactly as before. A manually uploaded document next to a promoted one stays through confirmation and regeneration.
- **Two decisions.** A manually uploaded contract document next to a promoted copy gives the contract two documents of kind contract; nothing removes the manual one. If a person deletes the promoted Document, the generated row loses its link (the file itself stays with the generated record) and a later confirmation promotes the current copy again.
- **No four-eyes rule on the confirmation.** `ConfirmRedaction` has never required a person different from the submitter (the four-eyes rule applies to the judgment gates return, approve and reject), and P6 keeps it that way: the editor who generated the copy may confirm it. The confirmation is still a human step; nothing is promoted or published by generating.
- **Reference counter (P7).** The yearly per-organization counter, the `{N}` / `{YYYY}` pattern per template, skipping of taken references and the rollback with a failed generation are shipped (see "The internal number") and need nothing further.

## Roles (step P6)

| Action | Who |
|---|---|
| Manage contract templates and import them (`:contract_template`, any of read, create, update, destroy, import) | organization admin with accepted admin terms only (the permission exists for the upcoming upload screen; today the import is the rake task, run by an operator) |
| Municipality header (`:organization_profile`) | organization admin with accepted admin terms only |
| Generate a contract from a template, regenerate | editor (`:create` / `:update` on `:contract`; regeneration only while the contract is editable) |
| Download the internal copy (personal data) | editor |
| Download the publication PDF | any engine role holder |

The older `:template` subject (contract skeletons that prefill the new-contract form, #127) is a different feature and keeps its editor-only rule.

## Parties of a contract from a template

A contract generated from a template gets its parties (the public catalogue page, the CRZ handoff and the exports read them), created in the same transaction as the documents by `Admin::SyncTemplateParties`:

| Party | Role | Source |
|-------|------|--------|
| the municipality | `object` (the contracting body) | the header profile: `official_name` (else the organization's name), `ico`, `seat` |
| the counterparty | `contractor` | the template's declared counterparty fields (below); none declared, none created |

The role vocabulary is the catalogue's own (`object` / `contractor`); the contract's role titles (predávajúci, kupujúci, prenajímateľ, nájomca) stay in the document text.

**Declaring the counterparty** (sidecar, `party_part` on the fields):

```yaml
person: [kupujuci_meno, kupujuci_adresa]
counterparty: { name: kupujuci_meno }                 # a natural person
# a company: plain (non-person) fields
counterparty: { name: partner_nazov, ico: partner_ico, address: partner_sidlo }
```

- **Natural person** (the `name` field is in `person`): the party is stored and published as **"Fyzická osoba"** only. No typed value is read for it, so no name, address, birth date or birth number reaches the `parties` table; the real values stay in the encrypted entry. The party has no IČO, so the existing rules keep it out of every public aggregate: the open-data exports list only parties with an IČO, the party filter matches names only among parties with an IČO, supplier pages and statistics rankings need an IČO. The catalogue page and the CRZ handoff show "Fyzická osoba" with the role. `ico` and `address` may not be declared next to a person name (the import refuses it).
- **Company** (the `name` field is not a person field): name, IČO and seat are stored as typed. The IČO (spaces ignored) must be eight digits or the form refuses it; it is optional. A company is published like any contractor, with a supplier page when it has an IČO. A sole trader (SZČO) is a natural person with an IČO; declare it as a company only if its name may be published.
- **Regenerating** updates the same two parties in place (they carry `template_slot` `municipality` / `counterparty`, unique per contract), so there are no duplicates, and a changed header or counterparty is picked up. A party a person added by hand has no slot and is never touched. If a person edits an auto-created party in the admin, the next regeneration overwrites it from the template; add a second party by hand instead. Emptying an optional counterparty name removes the counterparty party the template created.
- **Existing templates** have no declared counterparty: contracts regenerated from them gain the municipality only. Re-import the template with the sidecar `counterparty` setting as the next version (new contracts use it; contracts already written stay on their version and the version's fields are frozen).

**Updating a template that is already on a host** (for example the two demo templates): add `counterparty: { name: kupujuci_meno }` (purchase) or `counterparty: { name: najomca_meno }` (lease) to the sidecar and run the import again with the same `lineage_key`; this creates version 2 and archives version 1:

```bash
bin/rails "decidim_contracts_sk:templates:import[<org_id>,KZ-civora.docx,<lineage_key>,<Template name>]"
```

New contracts then get their parties; to give an existing draft its parties, use "Upraviť údaje a vygenerovať znova" on a version-2 contract (a contract pinned to version 1 keeps getting the municipality only).

### Schema

Two additive, reversible migrations, no backfill, hosts copy them verbatim: `20261103000010` adds the nullable string `parties.template_slot` and a unique index on `(contract_id, template_slot)` (NULLs are distinct, so manual parties are unrestricted); `20261103000011` adds the nullable string `contract_template_fields.party_part` (`name`, `ico` or `address`).

## Author guide: making a template in Word (step D1)

1. **Write the contract in Word as usual** and save it as `.docx`. An old `.doc` must be opened in Word or LibreOffice and saved as `.docx` first.
2. **Mark every place to fill with a merge field.** In Word: *Insert, Quick Parts, Field, MergeField*, and type the name with a leading equals sign, e.g. `=kupujuci_meno`. The field code must read `MERGEFIELD =kupujuci_meno \* MERGEFORMAT`. The name is lowercase ASCII with underscores (`a-z`, `0-9`, `_`; at most 64 characters), no diacritics, no spaces. The same field may appear several times (an IBAN used three times is filled once).
3. **Name the fields by what they are.** The names in "What a template author names" decide the treatment: `org_*` come from the municipality header, `cislo_zmluvy` is the internal number, `<amount>_slovom` is the amount in words. Everything else is asked for in the form; the type is guessed from the name (`datum_*` date, `cena_*` / `suma_*` money, otherwise text) and refined in the sidecar.
4. **Do not use** macros, embedded objects, linked files, tracked changes, hidden text or fields other than `MERGEFIELD`, `PAGE` and `NUMPAGES`. The import refuses such a file and says why. Control fields (conditions and loops) are not supported by the form yet.
5. **Mark personal data.** List in the sidecar every field that holds a natural person's data (name, birth number, address, a second person). Those values are stored encrypted and replaced in the publication copy. If one slips through unmarked, the redaction check refuses to generate and nothing is stored.
6. **Write the sidecar** `<file>.docx.fields.yml` next to the file (optional, but needed for personal fields, captions and groups):

   ```yaml
   person: [kupujuci_meno, kupujuci_rc, kupujuci_adresa]   # personal data
   required: [predmet, suma_celkom]                        # or: required: all
   types: { vymera: number, popis: long_text }             # text long_text date money number
   labels: { kupujuci_meno: "Kupujúci - meno" }            # the caption of a field
   groups: { kupujuci_meno: kupujuci, kupujuci_adresa: kupujuci }
   group_labels: { kupujuci: "Kupujúci" }                  # the heading of a group
   counterparty: { name: kupujuci_meno }                   # the other party of the contract (see "Parties of a contract from a template")
   ```

   `labels` defaults to the humanized key. `group_labels` keys must be groups some field uses. Unknown keys and fields the template does not have are errors, so a typo cannot pass silently.
7. **Import it** (an operator runs this on the host; the file stays outside git):

   ```bash
   bin/rails "decidim_contracts_sk:templates:import[<org_id>,<path/to/file.docx>,<lineage_key>,<Template name>]"
   ```

   The task prints the fields it created with their types. Importing the same `lineage_key` again creates the next version; contracts already written keep their version.
8. **Try it with invented data** (section "Walkthrough" in the manual scenarios), open both PDFs and check that the publication copy has no personal value.

### Redaction check: words shared with public content

The redaction check looks for each personal value as a whole, for the rodné číslo (with and without the slash) and, for multi-word values such as an address, for each longer word on its own. A buyer living in the municipality shares words with the public copy ("Považská Bystrica" in the header, in the katastrálne územie, in the template's own text), and those words alone are not a leak. So a per-word needle is dropped when the same word (compared without diacritics and case) appears in the template's own text (body, headers, footers) or in a non-personal value that went into the document (the `org_*` header fields, the katastrálne územie and every other field not marked personal).

- The whole-value needle and the rodné číslo needles are never exempted: the full address in the publication copy still fails, even when each of its words is public.
- A word that only a personal field holds (the street, the surname) stays a needle.
- Known trade-off: a personal word typed into a non-personal field counts as public content for the per-word check; the whole value is still caught.
- `RedactionVerifier.call(..., public_texts: [...])` takes the public strings; without it nothing is exempted (fail closed). `DocumentGenerator` passes the template text and the non-personal values.
