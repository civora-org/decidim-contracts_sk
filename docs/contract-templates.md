# Contract templates: schema and host requirements

Step P1 of [civora-org/civora-platform#211](https://github.com/civora-org/civora-platform/issues/211). This step ships the schema and the models only. There is no UI, no generation and no controller yet; those come in later steps (see the issue). Toolchain findings: [spikes/contract-templates-toolchain.md](spikes/contract-templates-toolchain.md).

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
- The engine adds `personal_values` to `config.filter_parameters`, and Active Record already filters it from `inspect`. The host's own log and error-reporting setup should not be loosened.

The engine's specs use fixed, public test keys set in `spec/dummy/config/application.rb`. They exist only for deterministic tests and must never be reused in a real host.

## Migrations

Six additive, reversible creates, dated 2026-10-20 (never in the future; see `migration_timestamps_spec.rb`). Hosts copy them verbatim with their original timestamps (README: "Upgrading the engine"), after the engine's earlier migrations. They need no backfill and touch no existing table. The host already owns the ActiveStorage tables the file attachments use.
