# E-mail alerts for new contracts

Landed in civora-org/civora-platform#121 (epic #114). A resident (no account) subscribes an e-mail address to a catalogue search and gets a digest when new contracts matching it are published. This is the engine's first table of resident personal data, so everything below is deliberately minimal. The DPIA input for civora-org/civora-platform#135 is at the end.

## What a resident sees

1. On the catalogue page, under the "Download data" block, an **E-mail alerts** block with an address field. It subscribes to exactly the search shown (the same normalized filters as the download links, never the sort). It is absent for the `source=crz` filter. `GET /zmluvy/subscriptions/new` is the same form on a page of its own (where a rejected address lands, with the error).
2. After submitting: a "Check your inbox" page. The page and the response never reveal whether the address was already subscribed.
3. A confirmation e-mail. Its link opens a page with a button; **only the button's POST confirms** (a mail scanner that opens the link cannot opt anybody in). Until then nothing else is sent.
4. A digest e-mail whenever something new matches. Every e-mail (confirmation included) has an unsubscribe link in the footer and the `List-Unsubscribe` and `List-Unsubscribe-Post: List-Unsubscribe=One-Click` headers. The link opens a page with one button; its POST deletes the subscription. A mail client's own one-click "Unsubscribe" POSTs straight to the same URL.

## Endpoints (mounted at `/zmluvy`)

| Verb and path | Purpose |
|---|---|
| `GET /subscriptions/new` | the form page |
| `POST /subscriptions` | create an unconfirmed subscription and send the confirmation mail |
| `GET`/`POST /subscriptions/:token/confirm` | confirmation page / confirm (raw random token) |
| `GET`/`POST /subscriptions/:token/unsubscribe` | unsubscribe page / delete the row (signed id; the POST needs no CSRF token) |

All of them are `noindex`, `Cache-Control: no-store`, `Referrer-Policy: no-referrer`, and every token lookup is scoped to the current organization. `GET /subscriptions` alone falls to the `/:id` catch-all (a 404).

## What is stored, and for how long

One table, `decidim_contracts_sk_subscriptions`. A pending row lives 48 hours at most; a confirmed row until the resident unsubscribes (it is **deleted**, no flag is kept).

| Column | Content | Notes |
|---|---|---|
| `decidim_organization_id` | tenant | no foreign key (the contracts table's precedent) |
| `email` | the address | stripped, lower-cased, max 254 |
| `filter_params` | JSON, `CatalogueQuery#to_params` minus `sort` | what the catalogue would apply: an invalid value is dropped, a reversed range swapped |
| `locale` | language of the mails | |
| `confirmed_at` | NULL until the double opt-in | |
| `last_notified_at` | end of the window already delivered | set to `confirmed_at` on confirmation, so no backlog is ever mailed |
| `token_digest` | SHA-256 hex of the confirmation token | the raw token exists only in the confirmation e-mail |
| `created_at`, `updated_at` | | the 48 hour expiry runs from `created_at` |

Not stored anywhere: IP address, user agent, a user reference (anonymous, a signed-in visitor is treated the same), name, open or click tracking. The rate limiter holds SHA-256 digests of the address and the IP in process memory for one hour; nothing about them reaches the database or the log. The unsubscribe token is a **signed id** (`ActiveRecord` `signed_id`, purpose-bound, no expiry), so later e-mails can carry one although no raw token is kept; it dies when the row is deleted or the host rotates `secret_key_base`.

## Rules

- **Own records only**, like the export and the feed: `Contract.open_data(organization)`, the organization's lifecycle-published records, never CRZ mirrors. A search restricted to `source=crz` is refused (it could never match).
- **Matching** is the catalogue's own `CatalogueQuery` over the stored filters, so alerts and the page can never disagree. "New" means `published_at` after the subscription's `last_notified_at`.
- **Digest, not per-contract mail.** One mail per subscription per run, listing the newest 20 matches (title with a public link, reference, amount, signing date) and the total, with a catalogue link for the rest. A CRZ-sized batch publish is one mail. Nothing matching, nothing sent. Parties are never printed (so no party without an IČO can appear).
- **No duplicates.** Each subscription is handled under its row lock and `last_notified_at` moves to the end of the window only after the mail left, so a second or concurrent run finds an empty window. The window ends one minute before the run (`SETTLE`), so a record whose publishing transaction was still committing is picked up next time.
- **Fail-soft.** One failing subscription is logged (class and subscription id only, never the address), counted, and retried by the next run (its window stays open); it never stops the others.
- **Limits.** At most 5 active subscriptions per address and organization (a pending duplicate of the same search is replaced, which doubles as a resend). Beyond that the response is the same "Check your inbox" page, with no mail.
- **Rate limit** of `POST /subscriptions`: 3 per address and 10 per client IP per hour, answered with 429. In-process (a host with several workers allows that many times the limit); see Host setup.
- **Escaping.** The mail views use plain ERB interpolation, never `_html` translations or `html_safe` on contract or search data.

## Host setup

1. **Run the migration** (`bin/rails decidim_contracts_sk:install:migrations`, then `db:migrate`) in the host. Reversible; `down` drops the table.
2. **Schedule the delivery** once a day (cron, the host's job runner):

   ```bash
   bin/rails decidim_contracts_sk:subscriptions:deliver                      # every organization
   bin/rails "decidim_contracts_sk:subscriptions:deliver[<organization_id>]" # one
   ```

   It prints `organization <id>: purged=… checked=… delivered=… failed=…` (counts only) and also purges the expired pending rows. `bin/rails decidim_contracts_sk:subscriptions:purge_expired` purges only. A run that finds nothing is a cheap no-op.
3. **Mail.** The mails use Decidim's mailer base, layout and sender, so the host's SMTP configuration applies. The confirmation is sent synchronously (`deliver_now`, so the raw token never sits in a job queue); a failure removes the row and shows "could not be sent". The digest is sent from the rake task.
4. **Optional global rate limit.** Add Rack::Attack in front of `POST <mount>/subscriptions` (Decidim's own `rack_attack` initializer is the place). The engine's limiter is the floor that works without it.
5. **Logs.** The confirmation and unsubscribe tokens are path segments, so a request log line carries them. They only confirm or delete that one subscription and the log is already a privileged store, but a host that wants them out adds a filter for `/subscriptions/<token>/` to its log pipeline. `email` is a default Rails `filter_parameters` entry; check the host keeps it.
6. **`secret_key_base` rotation** invalidates every outstanding unsubscribe link (their `List-Unsubscribe` headers too); rotate it deliberately.
7. **Controller role.** Per the legal-compliance doc the municipality is the data controller and Civora the processor; the DPA must cover the subscriber addresses (DPIA note below).

## Tests

`spec/requests/subscriptions_spec.rb` (form, double opt-in, tampering, expiry, unsubscribe including the CSRF exemption, rate limit, non-disclosure), `spec/decidim/contracts_sk/subscription_spec.rb`, `create_subscription_spec.rb`, `deliver_subscription_digests_spec.rb`, `subscription_mailer_spec.rb` (headers, escaping, locale), `subscription_throttle_spec.rb`, `subscriptions_task_spec.rb`, `spec/db/migrate/create_decidim_contracts_sk_subscriptions_spec.rb` (pins the column list), and the route pins in `engine_routing_spec.rb`. Every guard was mutation-checked.

## DPIA note (for civora-org/civora-platform#135)

- **New personal-data class:** the e-mail address of a resident (risk R23 of the threat model). Purpose: send the alerts the resident asked for. No profiling, no sharing, no analytics.
- **Legal basis:** consent (GDPR Art. 6(1)(a)), given by the double opt-in, withdrawable at any time by the unsubscribe link in every e-mail. The confirmation timestamp is the consent record.
- **Data minimisation:** the column list above is the complete record; the migration spec pins it.
- **Retention:** unconfirmed requests 48 hours; confirmed until unsubscribe; unsubscribe deletes the row immediately and completely (no flag, no log of the address). There is no soft delete and no archive. A municipality's backups follow their own cycle (#136); a deleted row can persist in a backup until it rotates out.
- **Recipients and processors:** the host's SMTP provider sees the address and the mail; the municipality is the controller, Civora the processor (DPA needed). No other recipient.
- **Rights:** access and erasure are served by the same row (find by address, delete); there is no self-service export, because the only data is what the subscriber typed.
- **Security:** 256-bit random confirmation token stored only as a digest; signed unsubscribe id; state changes only on POST; rate limit; no address shown in any response; non-disclosure of existing subscriptions; no IP stored; tokens never in referrers or caches.
- **Residual risks:** (1) the in-process rate limit is per worker, so a determined sender can use the form to send up to 3 confirmation e-mails per address per hour per worker to a third party (mitigated by the 5 per address cap, the neutral confirmation mail and the fact that the mail carries only the municipality's name; Rack::Attack closes it); (2) tokens appear in request logs (above); (3) the confirmation mail is sent to an address the requester typed, so it can be unwanted (hence the "ignore this e-mail" text and the one-click delete link in it).
