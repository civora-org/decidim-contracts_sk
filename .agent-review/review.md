# Agent Review

## Task
Pilot demo UX polish: guard blank live fields on public detail (#80), admin form a11y (#78), input hints + currency select (#79), localized money/date rendering + PDF timestamp UTC label (#81)

## Session
- Session ID: 6b2892c2-9985-4b7a-9031-fc723f7302c9
- Branch: polish/pilot-demo-ux
- Started: 2026-09-28T15:48:32.593Z
- Finished: 2026-09-28T16:25:37.886Z

## Summary
Public contract detail rendering (app/views/decidim/contracts_sk/contracts/show.html.erb): civora-org/civora-platform#80: the live dt/dd pairs (and the metadata line's date/amount spans) render unconditionally except crz_url, so a sparse published record shows an empty subject dd and a dangling EUR dd; each optional pair is now guarded on value presence, mirroring the frozen-snapshot section and the PDF export which already drop blank rows; title/reference stay unconditional (NOT NULL) Admin form partials accessibility (contracts/parties/documents/amendments _form.html.erb): civora-org/civora-platform#78: validation-error summaries render as a bare ul on 422 re-render and presence-validated inputs carry no required attribute; the ul gets role="alert" tabindex="-1" autofocus and required: true lands on contract title/reference, party name, amendment summary, document file — minimal engine-side a11y, matching the Decidim FormBuilder's supported field options Admin contract form amount input + IČO hint + currency select: civora-org/civora-platform#79: the amount field accepts only dot-decimals (STRICT_AMOUNT_FORMAT on the form) but says nothing about it, the IČO format rule is invisible to editors, and currency is a free-text input over a one-entry allowlist; hints get explicit ids wired with aria-describedby (the pinned Decidim FormBuilder's help_text: option renders neither id nor aria), and the select copies the role/kind select pattern over the frozen vocabulary Localized money/date rendering + CRZ handoff PDF timestamp zone label: civora-org/civora-platform#81: "1250.5 EUR" renders locale-blind while the audience is Slovak, every date renders naive to_fs(:db), and the PDF footer stamps a naive server-local time with no zone; a small helper in the base ApplicationHelper (number_with_precision with explicit sk separators; I18n.l with an explicit engine-shipped format string — the harness has no rails-i18n sk data, so named formats/day names would not resolve) replaces every to_fs(:db) date render and both amount renders, and the PDF footer converts to UTC explicitly

## Logical Changes

### 1. Localized money/date rendering + CRZ handoff PDF timestamp zone label
- What changed: modified in `app/helpers/decidim/contracts_sk/application_helper.rb`, `app/views/decidim/contracts_sk/contracts/show.html.erb`, `app/views/decidim/contracts_sk/contracts/index.html.erb`, `app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb`, `app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb`, `app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb`, `app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb`, `config/locales/en.yml`, `config/locales/sk.yml`
- Why: civora-org/civora-platform#81: "1250.5 EUR" renders locale-blind while the audience is Slovak, every date renders naive to_fs(:db), and the PDF footer stamps a naive server-local time with no zone; a small helper in the base ApplicationHelper (number_with_precision with explicit sk separators; I18n.l with an explicit engine-shipped format string — the harness has no rails-i18n sk data, so named formats/day names would not resolve) replaces every to_fs(:db) date render and both amount renders, and the PDF footer converts to UTC explicitly
- Expected behavior: Amounts render locale-aware: sk "1 250,50 EUR" (regular-space grouping, comma decimals — documented decision), en keeps the current fixed-point "1250.5 EUR"; dates render through a thin format_date helper backed by engine-shipped date_formats.default keys (sk "%d. %m. %Y", en "%Y-%m-%d" — no host-app locale data dependency); the PDF footer timestamp renders Time.current converted to UTC with an explicit " UTC" suffix; helper is PORO-safe (included by the PDF class)
- Risk: medium
### 2. Public contract detail rendering (app/views/decidim/contracts_sk/contracts/show.html.erb)
- What changed: modified in `app/views/decidim/contracts_sk/contracts/show.html.erb`
- Why: civora-org/civora-platform#80: the live dt/dd pairs (and the metadata line's date/amount spans) render unconditionally except crz_url, so a sparse published record shows an empty subject dd and a dangling EUR dd; each optional pair is now guarded on value presence, mirroring the frozen-snapshot section and the PDF export which already drop blank rows; title/reference stay unconditional (NOT NULL)
- Expected behavior: A published record carrying only title+reference renders no empty subject dd, no dangling EUR dd/span, no empty published-on/signed-on/effective-from dds; a full record renders unchanged; the metadata line under the title hides its date/amount spans when blank
- Risk: low
### 3. Admin form partials accessibility (contracts/parties/documents/amendments _form.html.erb)
- What changed: modified in `app/views/decidim/contracts_sk/admin/contracts/_form.html.erb`, `app/views/decidim/contracts_sk/admin/parties/_form.html.erb`, `app/views/decidim/contracts_sk/admin/documents/_form.html.erb`, `app/views/decidim/contracts_sk/admin/amendments/_form.html.erb`
- Why: civora-org/civora-platform#78: validation-error summaries render as a bare ul on 422 re-render and presence-validated inputs carry no required attribute; the ul gets role="alert" tabindex="-1" autofocus and required: true lands on contract title/reference, party name, amendment summary, document file — minimal engine-side a11y, matching the Decidim FormBuilder's supported field options
- Expected behavior: On a 422 re-render the error summary ul carries role="alert" tabindex="-1" autofocus; the presence-validated inputs render the required HTML attribute; no field-level aria-invalid/aria-describedby beyond the item-3 hints
- Risk: low
### 4. Admin contract form amount input + IČO hint + currency select
- What changed: modified in `app/views/decidim/contracts_sk/admin/contracts/_form.html.erb`, `app/views/decidim/contracts_sk/admin/parties/_form.html.erb`, `config/locales/en.yml`, `config/locales/sk.yml`, `spec/decidim/contracts_sk_locales_spec.rb`
- Why: civora-org/civora-platform#79: the amount field accepts only dot-decimals (STRICT_AMOUNT_FORMAT on the form) but says nothing about it, the IČO format rule is invisible to editors, and currency is a free-text input over a one-entry allowlist; hints get explicit ids wired with aria-describedby (the pinned Decidim FormBuilder's help_text: option renders neither id nor aria), and the select copies the role/kind select pattern over the frozen vocabulary
- Expected behavior: Amount input carries inputmode="decimal" and aria-describedby pointing at a localized hint that only dot-decimals are accepted; IČO input carries a localized blank-or-8-digits hint wired the same way; currency renders as a select over Contract::SUPPORTED_CURRENCIES (selected preserved) instead of a free-text input; hints shipped in en.yml and sk.yml and registered in the locale key-surface contract
- Risk: low

## Test Evidence

### Run 1
- Command: `bundle exec rspec`
- Result: **passed** (exit code: 0)
- Duration: 6330 ms
- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
### Run 2
- Command: `bundle exec rspec`
- Result: **passed** (exit code: 0)
- Duration: 8669 ms
- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
### Run 3
- Command: `CONTRACTS_SK_DB=1 bundle exec rspec`
- Result: **error** (exit code: signal)
- Duration: 8 ms
- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
- Notes: stderr captured (1 lines, redacted and truncated)
### Run 4
- Command: `env CONTRACTS_SK_DB=1 bundle exec rspec`
- Result: **passed** (exit code: 0)
- Duration: 50489 ms
- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`

## Risks
- Working tree was dirty at session start (17 entries) — pre-existing changes may be mixed into the diff.
- 1 test run(s) did not pass (exit codes: signal).

## Limitations
- Snapshots cover only files that were changed at checkpoint time.
- Symbol extraction is regex-based, not AST-based.
- Only observed facts are recorded — private model reasoning is not captured.

## Changed Files
- `.opencode/commands/agent-review-github-status.md` — added (markdown, +16/−0)
- `.opencode/commands/agent-review-prepare-pr.md` — added (markdown, +19/−0)
- `.opencode/commands/agent-review-publish-pr.md` — added (markdown, +19/−0)
- `.opencode/commands/agent-review-update-review.md` — added (markdown, +16/−0)
- `.opencode/plugins/agent-review.ts` — added (typescript, +357/−0)
- `.opencode/skills/agent-review` — added (unknown, +0/−0)
- `AGENTS.md` — modified (markdown, +2/−0)
- `app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb` — modified (ruby, +1/−7)
- `app/helpers/decidim/contracts_sk/application_helper.rb` — modified (ruby, +67/−0)
- `app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb` — modified (ruby, +28/−9)
- `app/views/decidim/contracts_sk/admin/amendments/_form.html.erb` — modified (unknown, +6/−4)
- `app/views/decidim/contracts_sk/admin/audit_events/index.html.erb` — modified (unknown, +4/−1)
- `app/views/decidim/contracts_sk/admin/contracts/_form.html.erb` — modified (unknown, +25/−7)
- `app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb` — modified (unknown, +1/−1)
- `app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb` — modified (unknown, +1/−1)
- `app/views/decidim/contracts_sk/admin/documents/_form.html.erb` — modified (unknown, +6/−3)
- `app/views/decidim/contracts_sk/admin/parties/_form.html.erb` — modified (unknown, +8/−5)
- `app/views/decidim/contracts_sk/contracts/index.html.erb` — modified (unknown, +5/−4)
- `app/views/decidim/contracts_sk/contracts/show.html.erb` — modified (unknown, +54/−22)
- `config/locales/en.yml` — modified (yaml, +4/−0)
- `config/locales/sk.yml` — modified (yaml, +4/−0)
- `docs/crz-import.md` — modified (markdown, +1/−1)
- `docs/qa-checklist.md` — modified (markdown, +7/−6)
- `opencode.jsonc` — modified (unknown, +6/−0)
- `spec/decidim/contracts_sk_locales_spec.rb` — modified (ruby, +30/−0)
- `spec/decidim/contracts_sk/application_helper_spec.rb` — added (ruby, +116/−0)
- `spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb` — modified (ruby, +9/−0)
- `spec/requests/admin/amendments_spec.rb` — modified (ruby, +8/−0)
- `spec/requests/admin/contracts_spec.rb` — modified (ruby, +34/−0)
- `spec/requests/admin/documents_spec.rb` — modified (ruby, +8/−0)
- `spec/requests/admin/parties_spec.rb` — modified (ruby, +10/−0)
- `spec/requests/contracts_spec.rb` — modified (ruby, +31/−0)

## Diff
```diff
diff --git a/AGENTS.md b/AGENTS.md
index d07b8da..1c4ccc3 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -133,6 +133,8 @@ Current lessons:
 
 - **The `with_lock` + in-lock re-check discipline applies to every command that writes state another request can change — not just lifecycle transitions.** Any guard (`draft?`, `published?`, `editable?`) evaluated on a request-loaded object is TOCTOU-bypassable: two concurrent publishes both pass the stale re-check and double-write. Wrap the write in `with_lock` (which reloads under lock) and re-check inside; read attributes the write depends on (snapshots, sequence numbers) from the post-lock instance. Test it deterministically with a stale pre-loaded object, no threads (proven in the #65 arc: reviewer H-1 on the amendment commands; `TransitionContract` was already the precedent).
 
+- **Close the previous agent-review session before starting a new arc, and expect `confirm:true` not to pass through.** A stale active session (e.g. a dry-run left over from a prior arc) blocks `agent_review_start` until the old session is finalized with `agent_review_build_package`; and the plugin's branch-creation confirmation can loop on `confirm:true`, in which case create the approved branch with plain `git checkout -b` and start the session on it (proven in the #87 arc).
+
 *Archived lessons (tracker & issue hygiene; engine mount-design; tooling & verification hygiene; host-app & ops; engine implementation mechanics; release-please; Decidim view & asset mechanics; live-source operations; issue & planning hygiene clusters) live in [`docs/retro-lessons.md`](docs/retro-lessons.md).*
 
 ## Testing Expectations
diff --git a/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb b/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
index 6db8a76..1f56f5f 100644
--- a/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
+++ b/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
@@ -26,7 +26,7 @@ module Decidim
       # admin contracts index (:read :contract): any engine role.
       class AuditEventsController < Admin::ApplicationController
         helper_method :audit_action_label, :audit_actor_name, :audit_target_info,
-                      :audit_reason_for, :audit_recorded_on
+                      :audit_reason_for
 
         # Deterministic index ordering: newest events first, id as the
         # tiebreaker (same doctrine as the contracts index — a total order,
@@ -183,12 +183,6 @@ module Decidim
         rescue StandardError
           nil
         end
-
-        # The event's timestamp, ISO date like the decision banner's
-        # decided-on line (nil-guarded the same way).
-        def audit_recorded_on(event)
-          event.created_at&.to_date&.to_fs(:db)
-        end
       end
     end
   end
diff --git a/app/helpers/decidim/contracts_sk/application_helper.rb b/app/helpers/decidim/contracts_sk/application_helper.rb
index 37d94a3..f55f5c2 100644
--- a/app/helpers/decidim/contracts_sk/application_helper.rb
+++ b/app/helpers/decidim/contracts_sk/application_helper.rb
@@ -9,7 +9,15 @@ module Decidim
     # imported records "externally confirmed" data — never a legal
     # publication — and ADR-008 decisions 4/6 require a freshness signal
     # that never implies real-time accuracy.
+    #
+    # Also carries the engine's locale-aware money/date/timestamp rendering
+    # (civora-org/civora-platform#81). The three formatters are deliberately
+    # PORO-safe — no view-context dependencies, I18n only — so the CRZ
+    # handoff PDF (a plain object) can include this module and share one
+    # formatting vocabulary with the views, never a second one.
     module ApplicationHelper
+      include ActionView::Helpers::NumberHelper
+
       # True when the record is a CRZ metadata mirror created by the import
       # ETL (ADR-008) rather than an editorial record. Drives every
       # provenance-labelled render in the catalogue; editorial records are
@@ -18,6 +26,47 @@ module Decidim
         contract.source == "crz"
       end
 
+      # Locale-aware amount rendering (civora-org/civora-platform#81).
+      # Under :sk the value is grouped and comma-decimalized — "1 250,50" —
+      # through number_with_precision with EXPLICIT separators: regular
+      # spaces (not non-breaking ones) were chosen on purpose, so the
+      # engine ships no glyph-dependent markup and the same string renders
+      # identically in HTML and in the PDF. Under every other locale the
+      # historical fixed-point form is kept verbatim (BigDecimal#to_s("F"),
+      # which also guards huge amounts against scientific notation). A
+      # blank amount renders empty; a blank currency renders the bare
+      # number — the PDF's drop-the-row semantics rely on both.
+      def format_amount(amount, currency = nil)
+        return "" if amount.blank?
+
+        formatted = localized_amount(amount)
+        return formatted if currency.blank?
+
+        "#{formatted} #{currency}"
+      end
+
+      # Locale-aware date rendering (civora-org/civora-platform#81): the
+      # format STRING is resolved from the engine's own
+      # decidim.contracts_sk.date_formats vocabulary and handed to I18n.l
+      # explicitly — never a named format, so no host-app or rails-i18n
+      # locale data can ever be required for the render to resolve. Blank
+      # renders empty, so guarded views may call it unconditionally.
+      def format_date(date)
+        return "" if date.blank?
+
+        I18n.l(date, format: I18n.t("decidim.contracts_sk.date_formats.default"))
+      end
+
+      # The PDF footer's generation stamp (civora-org/civora-platform#81):
+      # the timestamp is converted to UTC BEFORE formatting, so the naive
+      # to_fs(:db) digits can never silently carry the server's local zone
+      # — the label is explicit and true.
+      def format_timestamp(time)
+        return "" if time.blank?
+
+        "#{time.utc.to_fs(:db)} UTC"
+      end
+
       # True when a mirrored record must carry the stale notice (ADR-008
       # decision 4): the last import was stamped "failed" (the engine-side
       # stale-fallback signal — the record kept its last-good mirror data
@@ -38,6 +87,24 @@ module Decidim
 
         contract.imported_at < Decidim::ContractsSk.stale_after.to_i.seconds.ago
       end
+
+      private
+
+      # The locale branch of format_amount. Under :sk the value is grouped
+      # and comma-decimalized through number_with_precision; under every
+      # other locale the historical fixed-point form is kept verbatim —
+      # "F" on BigDecimal keeps extreme magnitudes out of scientific
+      # notation (plain BigDecimal#to_s goes scientific), while the frozen
+      # content snapshots' plain Strings render as stored.
+      def localized_amount(amount)
+        if I18n.locale == :sk
+          number_with_precision(amount, precision: 2, delimiter: " ", separator: ",")
+        elsif amount.is_a?(BigDecimal)
+          amount.to_s("F")
+        else
+          amount.to_s
+        end
+      end
     end
   end
 end
diff --git a/app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb b/app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb
index c714c2f..9e28f62 100644
--- a/app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb
+++ b/app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb
@@ -31,7 +31,17 @@ module Decidim
     # The contract is duck-typed (title, reference, state, subject_matter,
     # amount, currency, signed_on, effective_from, crz_url, parties), so the
     # renderer is testable without ActiveRecord.
+    #
+    # Money, dates and the footer stamp render through the engine's shared
+    # ApplicationHelper formatters (civora-org/civora-platform#81) — the
+    # PDF runs under I18n.with_locale(:sk), so they come out locale-aware
+    # ("1 250,50 EUR", "31. 01. 2026") — one formatting vocabulary with the
+    # views, never a second one. The footer stamp additionally converts the
+    # generation time to UTC explicitly and labels it, so the printed
+    # moment is never naive server-local time.
     class CrzHandoffPdf
+      include Decidim::ContractsSk::ApplicationHelper
+
       def initialize(contract)
         super()
         @contract = contract
@@ -82,7 +92,15 @@ module Decidim
 
       def render_footer(pdf)
         pdf.move_down 12
-        pdf.text "#{t("decidim.contracts_sk.crz_handoff_pdf.generated_on")} #{Time.current.to_fs(:db)}", size: 9
+        pdf.text "#{t("decidim.contracts_sk.crz_handoff_pdf.generated_on")} #{generated_stamp}", size: 9
+      end
+
+      # The footer's generation stamp (civora-org/civora-platform#81): the
+      # moment is converted to UTC BEFORE formatting and carries an explicit
+      # zone label, so a naive server-local "2026-09-27 09:53:07" can never
+      # be misread as registry time.
+      def generated_stamp
+        format_timestamp(Time.current)
       end
 
       # The identity + content field rows, in the data dictionary's order,
@@ -103,8 +121,8 @@ module Decidim
           [t("decidim.contracts_sk.contract.status"), state_label],
           [t("decidim.contracts_sk.contract.subject_matter"), contract.subject_matter],
           [t("decidim.contracts_sk.contract.amount"), amount_value],
-          [t("decidim.contracts_sk.contract.signed_on"), contract.signed_on&.to_fs(:db)],
-          [t("decidim.contracts_sk.contract.effective_from"), contract.effective_from&.to_fs(:db)],
+          [t("decidim.contracts_sk.contract.signed_on"), format_date(contract.signed_on)],
+          [t("decidim.contracts_sk.contract.effective_from"), format_date(contract.effective_from)],
           [t("decidim.contracts_sk.contract.crz_url"), contract.crz_url]
         ].select { |_, value| value.present? }
       end
@@ -119,15 +137,16 @@ module Decidim
         I18n.t("decidim.contracts_sk.contract_states.#{contract.state}", default: contract.state.to_s)
       end
 
-      # Fixed-point rendering on purpose: BigDecimal#to_s alone is
-      # scientific ("0.125e4"); the public catalogue's ERB interpolation
-      # hides that, a plain text draw would not. Nil when the amount is
-      # blank, so the row drops out of the field list.
+      # Locale-aware rendering on purpose (civora-org/civora-platform#81):
+      # under the PDF's forced :sk locale the shared formatter groups the
+      # thousands with regular spaces and comma-decimalizes ("12 345,67"),
+      # which also keeps BigDecimal's scientific to_s ("0.125e4") out of a
+      # plain text draw. Nil when the amount is blank, so the row drops out
+      # of the field list; a blank currency renders the bare number.
       def amount_value
         return nil if contract.amount.blank?
-        return contract.amount.to_s("F") if contract.currency.blank?
 
-        "#{contract.amount.to_s("F")} #{contract.currency}"
+        format_amount(contract.amount, contract.currency)
       end
 
       def t(key)
diff --git a/app/views/decidim/contracts_sk/admin/amendments/_form.html.erb b/app/views/decidim/contracts_sk/admin/amendments/_form.html.erb
index 46afb5d..39a41bf 100644
--- a/app/views/decidim/contracts_sk/admin/amendments/_form.html.erb
+++ b/app/views/decidim/contracts_sk/admin/amendments/_form.html.erb
@@ -2,14 +2,16 @@
     the summary is rendered — a draft amendment carries nothing else
     content-wise: the version is sequenced by the command and the content
     snapshot is taken at publish time from the contract's live fields
-    (civora-org/civora-platform#65, ADR-006). %>
-<%= form_with url: url, method: method, html: { class: "form form-defaults" } do |form| %>
+    (civora-org/civora-platform#65, ADR-006). The summary is the only
+    presence-validated input, so it alone carries the required attribute
+    (civora-org/civora-platform#78). %>
+<%= form_with model: @form, url: url, method: method, html: { class: "form form-defaults" } do |form| %>
   <div class="card">
     <div class="card-section">
       <div class="form__wrapper">
         <% if @form.errors.any? %>
           <div class="flash alert">
-            <ul>
+            <ul role="alert" tabindex="-1" autofocus>
               <% @form.errors.full_messages.each do |message| %>
                 <li><%= message %></li>
               <% end %>
@@ -18,7 +20,7 @@
         <% end %>
 
         <div class="row column">
-          <%= form.text_field :summary, label: t("decidim.contracts_sk.admin.amendments.form.summary"), label_options: { for: "amendment_summary" }, id: "amendment_summary", name: "amendment[summary]", value: @form.summary %>
+          <%= form.text_field :summary, label: t("decidim.contracts_sk.admin.amendments.form.summary"), label_options: { for: "amendment_summary" }, id: "amendment_summary", name: "amendment[summary]", value: @form.summary, required: true %>
         </div>
       </div>
     </div>
diff --git a/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb b/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb
index b93dc6e..1918976 100644
--- a/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb
+++ b/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb
@@ -51,7 +51,10 @@
                 <% end %>
               </td>
               <td><%= audit_actor_name(event) %></td>
-              <td><%= audit_recorded_on(event) %></td>
+              <%# The row date renders through the shared locale-aware helper
+                  (civora-org/civora-platform#81) directly in the view — the
+                  helper chain is the view's, not the controller's. %>
+              <td><%= format_date(event.created_at) %></td>
               <td><%= reason %></td>
             </tr>
           <% end %>
diff --git a/app/views/decidim/contracts_sk/admin/contracts/_form.html.erb b/app/views/decidim/contracts_sk/admin/contracts/_form.html.erb
index e52fb35..cdcee94 100644
--- a/app/views/decidim/contracts_sk/admin/contracts/_form.html.erb
+++ b/app/views/decidim/contracts_sk/admin/contracts/_form.html.erb
@@ -2,14 +2,23 @@
     the editorial identity fields and the contract content fields
     (civora-org/civora-platform#75) are rendered — the lifecycle state and
     the system-stamped published_at are intentionally absent from every
-    admin form. %>
-<%= form_with url: url, method: method, html: { class: "form form-defaults" } do |form| %>
+    admin form.
+    Accessibility surface (civora-org/civora-platform#78/#79): the error
+    summary is announced as a live alert and focused on the 422 re-render;
+    the presence-validated identity inputs carry the required attribute
+    (the builder is bound to @form — the Decidim builder's required path
+    needs the object, and the explicit name/id options keep every field
+    name stable); the amount input declares its decimal keyboard and its
+    dot-decimal hint through aria-describedby (the Decidim builder's
+    help_text option wires neither an id nor the aria relation, so the
+    hint element is explicit). %>
+<%= form_with model: @form, url: url, method: method, html: { class: "form form-defaults" } do |form| %>
   <div class="card">
     <div class="card-section">
       <div class="form__wrapper">
         <% if @form.errors.any? %>
           <div class="flash alert">
-            <ul>
+            <ul role="alert" tabindex="-1" autofocus>
               <% @form.errors.full_messages.each do |message| %>
                 <li><%= message %></li>
               <% end %>
@@ -18,11 +27,11 @@
         <% end %>
 
         <div class="row column">
-          <%= form.text_field :title, label: t("decidim.contracts_sk.admin.contracts.form.title"), label_options: { for: "contract_title" }, id: "contract_title", name: "contract[title]", value: @form.title %>
+          <%= form.text_field :title, label: t("decidim.contracts_sk.admin.contracts.form.title"), label_options: { for: "contract_title" }, id: "contract_title", name: "contract[title]", value: @form.title, required: true %>
         </div>
 
         <div class="row column">
-          <%= form.text_field :reference, label: t("decidim.contracts_sk.admin.contracts.form.reference"), label_options: { for: "contract_reference" }, id: "contract_reference", name: "contract[reference]", value: @form.reference %>
+          <%= form.text_field :reference, label: t("decidim.contracts_sk.admin.contracts.form.reference"), label_options: { for: "contract_reference" }, id: "contract_reference", name: "contract[reference]", value: @form.reference, required: true %>
         </div>
 
         <div class="row column">
@@ -30,11 +39,20 @@
         </div>
 
         <div class="row column">
-          <%= form.text_field :amount, label: t("decidim.contracts_sk.admin.contracts.form.amount"), label_options: { for: "contract_amount" }, id: "contract_amount", name: "contract[amount]", value: @form.amount %>
+          <%= form.text_field :amount, label: t("decidim.contracts_sk.admin.contracts.form.amount"), label_options: { for: "contract_amount" }, id: "contract_amount", name: "contract[amount]", value: @form.amount, inputmode: "decimal", aria: { describedby: "contract_amount_hint" } %>
+          <span class="help-text" id="contract_amount_hint"><%= t("decidim.contracts_sk.admin.contracts.form.amount_hint") %></span>
         </div>
 
         <div class="row column">
-          <%= form.text_field :currency, label: t("decidim.contracts_sk.admin.contracts.form.currency"), label_options: { for: "contract_currency" }, id: "contract_currency", name: "contract[currency]", value: @form.currency %>
+          <%# The options come from the model's frozen SUPPORTED_CURRENCIES
+              vocabulary (D1 of #75), never hand-enumerated. Currency ISO
+              codes are locale-neutral, so each option labels itself —
+              unlike the role/kind selects, no second localized vocabulary
+              is invented. %>
+          <% currency_options = Decidim::ContractsSk::Contract::SUPPORTED_CURRENCIES.map do |currency|
+               [currency, currency]
+             end %>
+          <%= form.select :currency, currency_options, { selected: @form.currency, label: t("decidim.contracts_sk.admin.contracts.form.currency"), label_options: { for: "contract_currency" } }, id: "contract_currency", name: "contract[currency]" %>
         </div>
 
         <div class="row column">
diff --git a/app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb b/app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb
index ff35bd4..122e891 100644
--- a/app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb
+++ b/app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb
@@ -12,7 +12,7 @@
                  (the index can show several confirmable rows on one page),
                  while the name stays the server-side contract. %>
 <% if contract.redaction_confirmed_at.present? %>
-  <p><%= t("decidim.contracts_sk.admin.contracts.confirm_redaction.confirmed_on", confirmed_at: contract.redaction_confirmed_at.to_date.to_fs(:db)) %></p>
+  <p><%= t("decidim.contracts_sk.admin.contracts.confirm_redaction.confirmed_on", confirmed_at: format_date(contract.redaction_confirmed_at)) %></p>
 <% else %>
   <p><%= t("decidim.contracts_sk.admin.contracts.confirm_redaction.description") %></p>
   <ul>
diff --git a/app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb b/app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb
index 328b99c..33e2cb1 100644
--- a/app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb
+++ b/app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb
@@ -9,6 +9,6 @@
 <p>
   <strong><%= t(contract.state, scope: "decidim.contracts_sk.contract_states") %></strong>
   — <%= t("decidim.contracts_sk.admin.contracts.review_decision.decided_on",
-          reviewed_at: contract.reviewed_at&.to_date&.to_fs(:db)) %>
+          reviewed_at: format_date(contract.reviewed_at)) %>
 </p>
 <p><%= contract.review_reason %></p>
diff --git a/app/views/decidim/contracts_sk/admin/documents/_form.html.erb b/app/views/decidim/contracts_sk/admin/documents/_form.html.erb
index d68b2df..a0a5efb 100644
--- a/app/views/decidim/contracts_sk/admin/documents/_form.html.erb
+++ b/app/views/decidim/contracts_sk/admin/documents/_form.html.erb
@@ -5,13 +5,13 @@
     civora-org/civora-platform#73). The kind options are derived from the
     form's EDITOR_KINDS vocabulary, never hand-enumerated, with localized
     labels. The form is multipart: the file travels with the request. %>
-<%= form_with url: url, method: method, html: { multipart: true, class: "form form-defaults" } do |form| %>
+<%= form_with model: @form, url: url, method: method, html: { multipart: true, class: "form form-defaults" } do |form| %>
   <div class="card">
     <div class="card-section">
       <div class="form__wrapper">
         <% if @form.errors.any? %>
           <div class="flash alert">
-            <ul>
+            <ul role="alert" tabindex="-1" autofocus>
               <% @form.errors.full_messages.each do |message| %>
                 <li><%= message %></li>
               <% end %>
@@ -38,7 +38,10 @@
         <% end %>
 
         <div class="row column">
-          <%= form.file_field :file, label: t("decidim.contracts_sk.admin.documents.form.file"), label_options: { for: "document_file" }, id: "document_file", name: "document[file]" %>
+          <%# The file is presence-validated on the form, so it carries the
+              required attribute on both the attach and the replace page
+              (civora-org/civora-platform#78). %>
+          <%= form.file_field :file, label: t("decidim.contracts_sk.admin.documents.form.file"), label_options: { for: "document_file" }, id: "document_file", name: "document[file]", required: true %>
         </div>
       </div>
     </div>
diff --git a/app/views/decidim/contracts_sk/admin/parties/_form.html.erb b/app/views/decidim/contracts_sk/admin/parties/_form.html.erb
index 8da1183..6f7a9c2 100644
--- a/app/views/decidim/contracts_sk/admin/parties/_form.html.erb
+++ b/app/views/decidim/contracts_sk/admin/parties/_form.html.erb
@@ -2,14 +2,16 @@
     the party's content fields are rendered — the parent contract is never
     form-writable (civora-org/civora-platform#76). The role options are
     derived from the model's frozen ROLES vocabulary, never hand-enumerated,
-    with localized labels. %>
-<%= form_with url: url, method: method, html: { class: "form form-defaults" } do |form| %>
+    with localized labels. The IČO hint (civora-org/civora-platform#79)
+    states the blank-or-8-digits rule the form validates, wired to the
+    input through aria-describedby. %>
+<%= form_with model: @form, url: url, method: method, html: { class: "form form-defaults" } do |form| %>
   <div class="card">
     <div class="card-section">
       <div class="form__wrapper">
         <% if @form.errors.any? %>
           <div class="flash alert">
-            <ul>
+            <ul role="alert" tabindex="-1" autofocus>
               <% @form.errors.full_messages.each do |message| %>
                 <li><%= message %></li>
               <% end %>
@@ -26,11 +28,12 @@
         </div>
 
         <div class="row column">
-          <%= form.text_field :name, label: t("decidim.contracts_sk.admin.parties.form.name"), label_options: { for: "party_name" }, id: "party_name", name: "party[name]", value: @form.name %>
+          <%= form.text_field :name, label: t("decidim.contracts_sk.admin.parties.form.name"), label_options: { for: "party_name" }, id: "party_name", name: "party[name]", value: @form.name, required: true %>
         </div>
 
         <div class="row column">
-          <%= form.text_field :ico, label: t("decidim.contracts_sk.admin.parties.form.ico"), label_options: { for: "party_ico" }, id: "party_ico", name: "party[ico]", value: @form.ico %>
+          <%= form.text_field :ico, label: t("decidim.contracts_sk.admin.parties.form.ico"), label_options: { for: "party_ico" }, id: "party_ico", name: "party[ico]", value: @form.ico, aria: { describedby: "party_ico_hint" } %>
+          <span class="help-text" id="party_ico_hint"><%= t("decidim.contracts_sk.admin.parties.form.ico_hint") %></span>
         </div>
 
         <div class="row column">
diff --git a/app/views/decidim/contracts_sk/contracts/index.html.erb b/app/views/decidim/contracts_sk/contracts/index.html.erb
index c8f9e43..653d6e7 100644
--- a/app/views/decidim/contracts_sk/contracts/index.html.erb
+++ b/app/views/decidim/contracts_sk/contracts/index.html.erb
@@ -30,9 +30,10 @@
             </span>
             <div class="card__list-text"><%= contract.reference %></div>
             <div class="card__list-metadata">
-              <%# Deterministic ISO rendering on purpose: the engine ships no
-                  locale date formats, so I18n.l would depend on host-app data. %>
-              <div><%= contract.published_at&.to_date&.to_fs(:db) %></div>
+              <%# Locale-aware date rendering (civora-org/civora-platform#81):
+                  the format string ships with the engine, so no host-app
+                  locale data is required. %>
+              <div><%= format_date(contract.published_at) %></div>
               <%# CRZ-mirror provenance (civora-org/civora-platform#88, ADR-002
                   rule 1): imported records are labelled externally confirmed,
                   with the mirror date — never presented as engine-published
@@ -44,7 +45,7 @@
                 <div class="text-sm text-gray-2">
                   <%= t("decidim.contracts_sk.provenance.badge") %>
                   <% if contract.imported_at.present? %>
-                    · <%= contract.imported_at.to_date.to_fs(:db) %>
+                    · <%= format_date(contract.imported_at) %>
                   <% end %>
                 </div>
               <% end %>
diff --git a/app/views/decidim/contracts_sk/contracts/show.html.erb b/app/views/decidim/contracts_sk/contracts/show.html.erb
index f71cb4d..bb1b708 100644
--- a/app/views/decidim/contracts_sk/contracts/show.html.erb
+++ b/app/views/decidim/contracts_sk/contracts/show.html.erb
@@ -7,11 +7,18 @@
     <h1 class="title-decorator"><%= @contract.title %></h1>
     <%# Quick-scan metadata line under the title: the record's identity
         (reference), its publication date and the headline amount. Uses the
-        existing contract vocabulary — no new keys. %>
+        existing contract vocabulary — no new keys. The optional fields are
+        guarded like the dl grid below (civora-org/civora-platform#80): a
+        sparse record renders no dangling date span and no "EUR" with a
+        blank amount. %>
     <div class="text-sm text-gray-2 flex gap-x-4">
       <span><%= t("decidim.contracts_sk.contract.reference_number") %>: <%= @contract.reference %></span>
-      <span><%= t("decidim.contracts_sk.contract.published_on") %>: <%= @contract.published_at&.to_date&.to_fs(:db) %></span>
-      <span><%= t("decidim.contracts_sk.contract.amount") %>: <%= @contract.amount %> <%= @contract.currency %></span>
+      <% if @contract.published_at.present? %>
+        <span><%= t("decidim.contracts_sk.contract.published_on") %>: <%= format_date(@contract.published_at) %></span>
+      <% end %>
+      <% if @contract.amount.present? %>
+        <span><%= t("decidim.contracts_sk.contract.amount") %>: <%= format_amount(@contract.amount, @contract.currency) %></span>
+      <% end %>
     </div>
   </section>
 
@@ -32,9 +39,9 @@
     <section class="mt-8 border-t border-gray-3 pt-4">
       <div class="font-semibold"><%= t("decidim.contracts_sk.provenance.badge") %></div>
       <% if @contract.imported_at.present? %>
-        <%# Deterministic ISO rendering, same rule as the metadata line above. %>
+        <%# Same localized date rule as the metadata line above. %>
         <div class="text-sm text-gray-2">
-          <%= t("decidim.contracts_sk.provenance.imported_on") %> <%= @contract.imported_at.to_date.to_fs(:db) %>
+          <%= t("decidim.contracts_sk.provenance.imported_on") %> <%= format_date(@contract.imported_at) %>
         </div>
       <% end %>
       <% if mirror_stale?(@contract) %>
@@ -56,24 +63,39 @@
       <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.reference_number") %></dt>
       <dd class="text-md text-black mt-0"><%= @contract.reference %></dd>
 
-      <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.published_on") %></dt>
-      <%# Deterministic ISO rendering on purpose: the engine ships no locale
-          date formats, so I18n.l would depend on host-app data. %>
-      <dd class="text-md text-black mt-0"><%= @contract.published_at&.to_date&.to_fs(:db) %></dd>
+      <%# The optional pairs are rendered only when the value is present
+          (civora-org/civora-platform#80) — the frozen-snapshot section and
+          the PDF export already drop blank rows, so the live grid must not
+          render empty dds and dangling currency labels for sparse records.
+          The reference stays unconditional: identity is NOT NULL. Dates and
+          amounts render through the shared locale-aware helpers
+          (civora-org/civora-platform#81). %>
+      <% if @contract.published_at.present? %>
+        <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.published_on") %></dt>
+        <dd class="text-md text-black mt-0"><%= format_date(@contract.published_at) %></dd>
+      <% end %>
 
-      <dt class="text-sm text-gray-2 md:col-span-2"><%= t("decidim.contracts_sk.contract.subject_matter") %></dt>
-      <dd class="text-md text-black mt-0 md:col-span-2"><%= @contract.subject_matter %></dd>
+      <% if @contract.subject_matter.present? %>
+        <dt class="text-sm text-gray-2 md:col-span-2"><%= t("decidim.contracts_sk.contract.subject_matter") %></dt>
+        <dd class="text-md text-black mt-0 md:col-span-2"><%= @contract.subject_matter %></dd>
+      <% end %>
 
-      <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.amount") %></dt>
-      <dd class="text-md text-black mt-0"><%= @contract.amount %> <%= @contract.currency %></dd>
+      <% if @contract.amount.present? %>
+        <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.amount") %></dt>
+        <dd class="text-md text-black mt-0"><%= format_amount(@contract.amount, @contract.currency) %></dd>
+      <% end %>
 
-      <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.signed_on") %></dt>
-      <dd class="text-md text-black mt-0"><%= @contract.signed_on&.to_fs(:db) %></dd>
+      <% if @contract.signed_on.present? %>
+        <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.signed_on") %></dt>
+        <dd class="text-md text-black mt-0"><%= format_date(@contract.signed_on) %></dd>
+      <% end %>
 
-      <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.effective_from") %></dt>
-      <dd class="text-md text-black mt-0"><%= @contract.effective_from&.to_fs(:db) %></dd>
+      <% if @contract.effective_from.present? %>
+        <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.effective_from") %></dt>
+        <dd class="text-md text-black mt-0"><%= format_date(@contract.effective_from) %></dd>
+      <% end %>
 
-      <%# The only guarded field: a link to a blank URL would render href="". %>
+      <%# The originally guarded field: a link to a blank URL would render href="". %>
       <% if @contract.crz_url.present? %>
         <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.crz_url") %></dt>
         <dd class="text-md text-black mt-0"><%= link_to @contract.crz_url, @contract.crz_url %></dd>
@@ -202,23 +224,33 @@
           <div class="font-semibold">
             <%= t("decidim.contracts_sk.contracts.show.version_label", version: amendment.version) %>
             <% if amendment.published_at.present? %>
-              · <%= amendment.published_at.to_date.to_fs(:db) %>
+              · <%= format_date(amendment.published_at) %>
             <% end %>
           </div>
           <%# Same dl treatment as the current version's fields above — one
-              consistent key/value grid for both snapshot and live data. %>
+              consistent key/value grid for both snapshot and live data,
+              including the blank-value guards (#80) and the locale-aware
+              date/amount helpers (#81). %>
           <dl class="grid grid-cols-1 gap-x-8 gap-y-3 md:grid-cols-2">
             <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.summary") %></dt>
             <dd class="text-md text-black mt-0"><%= amendment.summary %></dd>
 
-            <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.published_on") %></dt>
-            <dd class="text-md text-black mt-0"><%= amendment.published_at&.to_date&.to_fs(:db) %></dd>
+            <% if amendment.published_at.present? %>
+              <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.published_on") %></dt>
+              <dd class="text-md text-black mt-0"><%= format_date(amendment.published_at) %></dd>
+            <% end %>
 
             <% amendment.content_snapshot.to_h.each do |field, value| %>
               <% next if value.blank? %>
               <% if field == "crz_url" %>
                 <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.crz_url") %></dt>
                 <dd class="text-md text-black mt-0"><%= link_to value, value %></dd>
+              <% elsif field == "amount" %>
+                <%# The frozen amount renders through the same locale-aware
+                    helper as the live fields (#81); the currency renders
+                    under its own row, exactly as stored. %>
+                <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.amount") %></dt>
+                <dd class="text-md text-black mt-0"><%= format_amount(value) %></dd>
               <% else %>
                 <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.#{field}") %></dt>
                 <dd class="text-md text-black mt-0"><%= value %></dd>
diff --git a/config/locales/en.yml b/config/locales/en.yml
index 1b6c4cb..9bcc9a8 100644
--- a/config/locales/en.yml
+++ b/config/locales/en.yml
@@ -33,6 +33,8 @@ en:
         heading: "CRZ handoff aid"
         disclaimer: "This document is a handoff aid for the CRZ record — not a legal publication."
         generated_on: "Generated on"
+      date_formats:
+        default: "%Y-%m-%d"
       menu:
         contracts: "Contracts"
         admin_contracts: "Contracts"
@@ -140,6 +142,7 @@ en:
             reference: "Reference"
             subject_matter: "Subject matter"
             amount: "Amount"
+            amount_hint: "Use a dot as the decimal separator (e.g. 1250.50) — comma decimals are rejected."
             currency: "Currency"
             signed_on: "Signed on"
             effective_from: "Effective from"
@@ -239,6 +242,7 @@ en:
             role: "Role"
             name: "Name"
             ico: "Company ID (IČO)"
+            ico_hint: "Leave blank or enter exactly 8 digits."
             address: "Address"
         documents:
           index:
diff --git a/config/locales/sk.yml b/config/locales/sk.yml
index 12d393e..b9ddf77 100644
--- a/config/locales/sk.yml
+++ b/config/locales/sk.yml
@@ -33,6 +33,8 @@ sk:
         heading: "Pomôcka na odovzdanie do CRZ"
         disclaimer: "Tento dokument je pomôcka na odovzdanie do CRZ — nie právna publikácia."
         generated_on: "Vygenerované"
+      date_formats:
+        default: "%d. %m. %Y"
       menu:
         contracts: "Zmluvy"
         admin_contracts: "Zmluvy"
@@ -140,6 +142,7 @@ sk:
             reference: "Číslo zmluvy"
             subject_matter: "Predmet zmluvy"
             amount: "Hodnota"
+            amount_hint: "Použite bodku ako oddeľovač desatinných miest (napr. 1250.50) — desatinná čiarka nie je prijateľná."
             currency: "Mena"
             signed_on: "Dátum podpisu"
             effective_from: "Dátum účinnosti"
@@ -239,6 +242,7 @@ sk:
             role: "Rola"
             name: "Názov"
             ico: "IČO"
+            ico_hint: "Nechajte prázdne alebo zadajte presne 8 číslic."
             address: "Adresa"
         documents:
           index:
diff --git a/docs/crz-import.md b/docs/crz-import.md
index bd2ea19..3e9ad7f 100644
--- a/docs/crz-import.md
+++ b/docs/crz-import.md
@@ -146,7 +146,7 @@ import writes — mirrors are labelled, never implied to be real-time
 (ADR-002 rule 1, ADR-008 decisions 4/6):
 
 - **Index card:** the "Externally confirmed" badge plus the mirror date
-  (`imported_at`, rendered as an ISO date). No stale indicator — cards
+  (`imported_at`, rendered as a localized date). No stale indicator — cards
   stay lean.
 - **Detail page:** a provenance block with the badge, the mirror date and
   the preserved attribution note (data via ekosystem.slovensko.digital;
diff --git a/docs/qa-checklist.md b/docs/qa-checklist.md
index 891b1c3..b0a4b62 100644
--- a/docs/qa-checklist.md
+++ b/docs/qa-checklist.md
@@ -69,7 +69,7 @@ ideally in both `en` and `sk` where noted.
 
 - [ ] The contract edit page links to the audit trail pre-filtered to that record; the link renders for every engine role.
 - [ ] The viewer lists the organization's events newest-first; a contract-filtered view shows the naming banner and the back-to-all link.
-- [ ] Rows show the localized action (lifecycle verbs, redaction confirmation, amendment publish, CRZ import), the target record, the acting user and the ISO date.
+- [ ] Rows show the localized action (lifecycle verbs, redaction confirmation, amendment publish, CRZ import), the target record, the acting user and the localized date.
 - [ ] A target whose record was deleted renders the localized "record no longer exists" label — no error, no internals (en + sk).
 - [ ] The decision-reason column fills only for records sitting in a decision state (returned/rejected) carrying a reason; everything else stays blank.
 - [ ] Localized empty state when the organization has no events (en + sk); pagination carries the contract filter across pages.
@@ -80,7 +80,7 @@ ideally in both `en` and `sk` where noted.
 - [ ] Every input labeled, ids unique per page (en + sk).
 - [ ] Confirm dialogs on ALL destroys, amendment publish and contract transitions; keyboard-operable.
 - [ ] Writes are POST/redirect/flash (no re-render on success); 422 re-renders keep values and show errors near the form top.
-- [ ] Money and dates render per convention — **DECISION RECORD**: ISO dates, fixed-point EUR amounts, no locale-dependent grouping (deterministic across hosts).
+- [ ] Money and dates render per convention — **DECISION RECORD** (civora-org/civora-platform#81): locale-aware rendering — under :sk amounts group thousands with a regular space and use comma decimals ("1 250,50 EUR") and dates render "01. 09. 2026"; under :en the historical ISO dates and fixed-point amounts ("1250.5 EUR") are kept. The date format strings and the sk separators ship with the engine (no host locale data), and the PDF footer stamp is UTC-converted and explicitly labelled "UTC".
 - [ ] Loading states: N/A (no async UI in the engine).
 - [ ] Mixed en/sk content: page `lang` is host-owned; spot-check that engine strings match the active locale even when record content is in the other language.
 - [ ] Keyboard-only full workflow pass: create → edit → parties → documents → redaction confirmation → submit → return → approve → publish → amendment → archive.
@@ -88,8 +88,9 @@ ideally in both `en` and `sk` where noted.
 
 ## Known gaps and follow-ups
 
-- Validation errors are visible but not announced to assistive tech; no required-field markers on forms — civora-org/civora-platform#78.
-- Hints for constrained inputs (dot-decimal amount, 8-digit IČO) and currency as a select — civora-org/civora-platform#79.
-- Sparse published records (nil amount / subject matter) render bare labels on the public detail page — civora-org/civora-platform#80.
 - CRZ handoff section disappears on a failed contract update re-render — civora-org/civora-platform#77.
-- Formatting conventions (ISO dates, ungrouped fixed-point money, PDF timestamp without zone) are deliberate V0.1 determinism pending a product decision — civora-org/civora-platform#81.
+
+<!-- Resolved by the pilot-demo-ux arc (civora-org/civora-platform#78, #79, #80, #81):
+     announced/focused 422 error summaries + required markers; amount/IČO hints and
+     the currency select; guarded blank live fields on the public detail page;
+     locale-aware money/date rendering and the UTC-labelled PDF stamp. -->
diff --git a/opencode.jsonc b/opencode.jsonc
index 79182e2..1feac13 100644
--- a/opencode.jsonc
+++ b/opencode.jsonc
@@ -39,6 +39,12 @@
     }
   },
   "mcp": {
+    "slov-lex": {
+      "type": "local",
+      "command": ["node", "/Users/denyskozlov/.local/share/slov-lex-mcp/dist/index.js"],
+      "enabled": true,
+      "environment": {}
+    },
     "playwright": {
       "type": "local",
       "command": ["npx", "-y", "@playwright/mcp@latest"],
diff --git a/spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb b/spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb
index d6549ce..828a097 100644
--- a/spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb
+++ b/spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb
@@ -90,4 +90,13 @@ RSpec.describe Decidim::ContractsSk::CrzHandoffPdf do
 
     expect { pdf_bytes }.not_to raise_error
   end
+
+  it "labels the footer generation stamp with an explicit UTC zone (civora-org/civora-platform#81)" do
+    # Byte-level content assertions are impossible (font-subset encoding —
+    # see the header), so the stamp is asserted through the method the
+    # footer draws: UTC-converted digits plus the zone label.
+    stamp = described_class.new(contract).send(:generated_stamp)
+
+    expect(stamp).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC\z/)
+  end
 end
diff --git a/spec/decidim/contracts_sk_locales_spec.rb b/spec/decidim/contracts_sk_locales_spec.rb
index cae4d40..202b223 100644
--- a/spec/decidim/contracts_sk_locales_spec.rb
+++ b/spec/decidim/contracts_sk_locales_spec.rb
@@ -448,6 +448,25 @@ module LocaleContract
   }.freeze
   # rubocop:enable Style/FormatStringToken
 
+  # The admin form hints and the engine-shipped date format per locale
+  # (civora-org/civora-platform#79, #81). The date format is a strftime
+  # STRING resolved by the engine's format_date helper — never a named I18n
+  # format, so no host-app or rails-i18n locale data is ever required.
+  FORM_HINT_AND_DATE_FORMAT_LABELS = {
+    en: {
+      "admin.contracts.form.amount_hint" =>
+        "Use a dot as the decimal separator (e.g. 1250.50) — comma decimals are rejected.",
+      "admin.parties.form.ico_hint" => "Leave blank or enter exactly 8 digits.",
+      "date_formats.default" => "%Y-%m-%d"
+    },
+    sk: {
+      "admin.contracts.form.amount_hint" =>
+        "Použite bodku ako oddeľovač desatinných miest (napr. 1250.50) — desatinná čiarka nie je prijateľná.",
+      "admin.parties.form.ico_hint" => "Nechajte prázdne alebo zadajte presne 8 číslic.",
+      "date_formats.default" => "%d. %m. %Y"
+    }
+  }.freeze
+
   # The exact expected leaf-key surface under decidim.contracts_sk, including
   # the public catalogue keys (plan Option B of #39), the admin CRUD keys
   # (civora-org/civora-platform#58), the admin content-field form keys
@@ -514,6 +533,7 @@ module LocaleContract
     "admin.contracts.create.success",
     "admin.contracts.edit.title",
     "admin.contracts.form.amount",
+    "admin.contracts.form.amount_hint",
     "admin.contracts.form.crz_url",
     "admin.contracts.form.currency",
     "admin.contracts.form.effective_from",
@@ -628,6 +648,7 @@ module LocaleContract
     "admin.parties.edit.title",
     "admin.parties.form.address",
     "admin.parties.form.ico",
+    "admin.parties.form.ico_hint",
     "admin.parties.form.name",
     "admin.parties.form.role",
     "admin.parties.index.empty",
@@ -678,6 +699,7 @@ module LocaleContract
     "crz_handoff_pdf.disclaimer",
     "crz_handoff_pdf.generated_on",
     "crz_handoff_pdf.heading",
+    "date_formats.default",
     "menu.admin_contracts",
     "menu.contracts",
     "pagination.aria_label",
@@ -1035,6 +1057,14 @@ RSpec.describe Decidim::ContractsSk do
       end
     end
 
+    it "translates the admin form hints and the engine date format in both locales (#79, #81)" do
+      LocaleContract::FORM_HINT_AND_DATE_FORMAT_LABELS.each do |locale, labels|
+        labels.each do |key, value|
+          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
+        end
+      end
+    end
+
     it "keeps the established Slovak party terminology on the public detail page (civora-org/civora-platform#63)" do
       PublicCatalogueLabels::PARTY_ROLE_LABELS.each do |locale, labels|
         labels.each do |role, value|
diff --git a/spec/requests/admin/amendments_spec.rb b/spec/requests/admin/amendments_spec.rb
index e93822c..c314b75 100644
--- a/spec/requests/admin/amendments_spec.rb
+++ b/spec/requests/admin/amendments_spec.rb
@@ -346,6 +346,14 @@ RSpec.describe "admin amendment management", type: :request do
       expect(response).to have_http_status(:unprocessable_entity)
       expect(flash[:alert]).to be_present
       expect(Decidim::ContractsSk::Amendment.count).to eq(0)
+      # The re-rendered form (civora-org/civora-platform#78): the announced,
+      # focused error summary and the required attribute on the
+      # presence-validated summary input.
+      aggregate_failures do
+        expect(response.body).to include('role="alert"')
+        expect(response.body).to include("autofocus")
+        expect(response.body).to include('required="required"')
+      end
     end
 
     it "denies a reviewer-only user on create" do
diff --git a/spec/requests/admin/contracts_spec.rb b/spec/requests/admin/contracts_spec.rb
index afa7649..e1b3935 100644
--- a/spec/requests/admin/contracts_spec.rb
+++ b/spec/requests/admin/contracts_spec.rb
@@ -409,6 +409,33 @@ RSpec.describe "admin contracts CRUD", type: :request do
     end
   end
 
+  describe "contract form rendering (offline, DB-free, civora-org/civora-platform#78, #79)" do
+    it "renders the accessible amount hint, the decimal input mode and the currency select" do
+      sign_in(roles: %i[editor])
+
+      get "/admin/contracts/new"
+
+      expect(response).to have_http_status(:ok)
+      aggregate_failures do
+        # Amount input (#79): decimal keyboard hint plus the localized
+        # dot-decimal hint, wired through aria-describedby to the hint's id.
+        expect(response.body).to include('inputmode="decimal"')
+        expect(response.body).to include('aria-describedby="contract_amount_hint"')
+        expect(response.body).to include('id="contract_amount_hint"')
+        expect(response.body).to include("Use a dot as the decimal separator")
+        # Currency (#79): a select over the allowlist with the default
+        # selected — never the free-text input again.
+        expect(response.body).to include(">EUR</option>")
+        expect(response.body).to include("selected=")
+        expect(response.body).not_to match(/<input[^>]*name="contract\[currency\]"/)
+        # Presence-validated identity inputs carry the required attribute
+        # (#78) — exactly two: title and reference.
+        expect(response.body.scan('required="required"').size).to eq(2)
+        expect(response.body).to include("label-required")
+      end
+    end
+  end
+
   describe "allowed and validation paths", :db do
     # The current_user belongs to the stubbed organization, like a real
     # signed-in editor — CreateContract's tenancy guard reads
@@ -587,6 +614,13 @@ RSpec.describe "admin contracts CRUD", type: :request do
 
       expect(response).to have_http_status(:unprocessable_entity)
       expect(Decidim::ContractsSk::Contract.count).to eq(0)
+      # The re-rendered form's error summary is announced and focused
+      # (civora-org/civora-platform#78) — a bare ul is an a11y regression.
+      aggregate_failures do
+        expect(response.body).to include('role="alert"')
+        expect(response.body).to include('tabindex="-1"')
+        expect(response.body).to include("autofocus")
+      end
     end
 
     it "answers 422 and persists nothing on a duplicate (organization, reference)" do
diff --git a/spec/requests/admin/documents_spec.rb b/spec/requests/admin/documents_spec.rb
index 41022a2..36def87 100644
--- a/spec/requests/admin/documents_spec.rb
+++ b/spec/requests/admin/documents_spec.rb
@@ -386,6 +386,14 @@ RSpec.describe "admin document management", type: :request do
 
       expect(response).to have_http_status(:unprocessable_entity)
       expect(Decidim::ContractsSk::Document.count).to eq(0)
+      # The re-rendered form (civora-org/civora-platform#78): the announced
+      # error summary and the required attribute on the presence-validated
+      # file input.
+      aggregate_failures do
+        expect(response.body).to include('role="alert"')
+        expect(response.body).to include("autofocus")
+        expect(response.body).to include('required="required"')
+      end
     end
 
     it "answers 422 with the alert and persists nothing when the kind is outside the vocabulary" do
diff --git a/spec/requests/admin/parties_spec.rb b/spec/requests/admin/parties_spec.rb
index b2eb2b6..4c81cdd 100644
--- a/spec/requests/admin/parties_spec.rb
+++ b/spec/requests/admin/parties_spec.rb
@@ -290,6 +290,16 @@ RSpec.describe "admin party management", type: :request do
       expect(response).to have_http_status(:unprocessable_entity)
       expect(flash[:alert]).to be_present
       expect(Decidim::ContractsSk::Party.count).to eq(0)
+      # The re-rendered form (civora-org/civora-platform#78, #79): the
+      # error summary is announced/focused, the required name input carries
+      # the attribute, and the IČO hint is wired through aria-describedby.
+      aggregate_failures do
+        expect(response.body).to include('role="alert"')
+        expect(response.body).to include("autofocus")
+        expect(response.body).to include('aria-describedby="party_ico_hint"')
+        expect(response.body).to include("Leave blank or enter exactly 8 digits.")
+        expect(response.body).to include('required="required"')
+      end
     end
 
     it "answers 422 with the alert and persists nothing when the role is outside the vocabulary" do
diff --git a/spec/requests/contracts_spec.rb b/spec/requests/contracts_spec.rb
index 8ca259f..639a844 100644
--- a/spec/requests/contracts_spec.rb
+++ b/spec/requests/contracts_spec.rb
@@ -402,6 +402,37 @@ RSpec.describe "public contracts catalogue", type: :request do
       end
     end
 
+    it "renders no blank field rows for a sparse published record (civora-org/civora-platform#80)" do
+      # Only the identity is filled: every optional live field is blank —
+      # the exact shape that used to render an empty subject dd and a
+      # dangling "EUR" dd (and metadata spans).
+      sparse = detail_contract_double(
+        published_at: Time.new(2026, 9, 1, 12, 0, 0),
+        subject_matter: nil,
+        amount: nil,
+        signed_on: nil,
+        effective_from: nil,
+        crz_url: nil
+      )
+      stub_published_contracts(double(find: sparse))
+
+      get "/7"
+
+      expect(response).to have_http_status(:ok)
+      aggregate_failures do
+        # The identity pair stays unconditional — title/reference are NOT NULL.
+        expect(response.body).to include("Road reconstruction")
+        expect(response.body).to include("ZP-2026-001")
+        # The guarded optional pairs disappear entirely: no blank dd
+        # placeholders, no dangling currency label next to a nil amount.
+        expect(response.body).not_to include("Subject matter")
+        expect(response.body).not_to include("EUR")
+        expect(response.body).not_to include("Signed on")
+        expect(response.body).not_to include("Effective from")
+        expect(response.body).not_to include('<dd class="text-md text-black mt-0"></dd>')
+      end
+    end
+
     it "renders the empty-party state gracefully" do
       stub_published_contracts(double(find: contract))
 

```

## Agent Activity
- Tool calls: 110
- Commands: 40
- Checkpoints: 3
- Test runs: 4
- Journal events: 3791

_Generated: 2026-09-28T16:25:37.850Z · schema agent-review/v1_
