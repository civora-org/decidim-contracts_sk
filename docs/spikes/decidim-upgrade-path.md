# Spike: Decidim upgrade path off the Rails 7.2 EOL line

Status: spike for [civora-org/civora-platform#141](https://github.com/civora-org/civora-platform/issues/141), written 2026-10-11. Nothing here has been run. Every compatibility claim is read from upstream sources; section 9 lists what still needs a real boot.

## 1. Where we are and which Decidim line is next

- **Today:** Decidim 0.31.7 pins `rails ~> 7.2.0`, Ruby `~> 3.3.0` and `shakapacker ~> 8.3.0` ([rubygems](https://rubygems.org/gems/decidim-core/versions/0.31.7)). Rails 7.2 reached end of life on 2026-08-09 ([endoflife.date](https://endoflife.date/rails)).
- **Next line:** Decidim 0.32.x. 0.32.0 was released 2026-07-02 and 0.32.1 on 2026-07-30 ([releases](https://github.com/decidim/decidim/releases/tag/v0.32.0), [versions](https://rubygems.org/gems/decidim/versions)).
- **What 0.32.1 pins:** `rails ~> 8.1.0`, Ruby `~> 3.4.0` (`.ruby-version` 3.4.7), `shakapacker ~> 9.7.0`, `rack >= 3.2.4, < 4`, `devise >= 4.7, < 6`, `image_processing ~> 1.2` with `ruby-vips ~> 2.2`. libvips replaces ImageMagick.
- **Other 0.32.1 pins:** `decidim-dev` allows `puma >= 6.5, < 8`, and `decidim-api` allows `graphql >= 2.4.17, < 2.6`. `rubyzip ~> 2.0` and `rack-proxy ~> 0.8.3` are unchanged.
- **Rails 8.1 support** runs until 2027-10-10; Rails 8.0 ends 2026-11-07. 0.32.0 went straight to Rails 8.1, with no 7.2 → 8.0 stepping stone.
- **Node and Postgres:** Node stays `>= 22.14.0`, and Decidim CI runs Postgres 14, so there is no change for us.
- **Support policy:** Decidim's [SECURITY.md](https://github.com/decidim/decidim/blob/develop/SECURITY.md) supports only the last two minors before 1.0. Today that is 0.32 and 0.31; 0.31 drops out when 0.33 ships. 0.33 has no date, but extrapolating the cadence puts it around Q1 2027.
- **Even while supported,** 0.31 will never receive the Rails 7.2 CVE fixes.

## 2. What the upgrade clears from `.bundler-audit.yml`

| Blocked advisory | Pin today | After 0.32.1 |
|---|---|---|
| Rails 7.2 EOL CVEs (10) | rails 7.2 | cleared (Rails 8.1) |
| devise 4.9.4 (2) | `~> 4.7` | cleared if the patched release is 5.x; verify |
| shakapacker 8.3 | `~> 8.3.0` | cleared (9.7) |
| puma (2) | decidim-dev `~> 6.5` | cleared (`< 8`) |
| graphql GHSA-rmxg | `~> 2.4.0` | not cleared (`< 2.6`; the fix needs `>= 2.6.9`) |
| rack-proxy GHSA-42qh | `< 1.0` | not cleared |
| rubyzip CVE-2026-85396 (High) | `~> 2.0` | not cleared |

About 15 of the 19 ignores go away. The rubyzip path traversal on extraction needs a documented mitigation either way.

## 3. Breaking changes mapped to this engine and the host

The source is the [v0.32.0 release notes](https://github.com/decidim/decidim/releases/tag/v0.32.0).

### Engine

| 0.32 change | Impact | Verdict |
|---|---|---|
| Menu API | `lib/decidim/contracts_sk/menu.rb`: `menu.rb` / `menu_registry.rb` differ between v0.31.7 and v0.32.1 only in YARD comments | no change |
| `Decidim::Admin::ApplicationController` | identical blob in both tags | no change |
| `.layout-1col` | still defined in `decidim-core` `_layout.scss` | no change |
| `.cs-` engine stylesheet | the engine owns its CSS | visual check only |
| `ActiveSupport::Configurable` removed | the engine has no `config_accessor` / `Configurable` | no change |
| Locale-prefixed URLs (`/sk/...`) | open-data URLs, public permalinks, CRZ handoff links, canonical/sitemap URLs | **verify**: highest functional risk |
| Rack 3.2 | `:unprocessable_entity` in 8 files gives deprecation warnings | low |
| Rails 8.1 | run the full `:db` suite; watch `with_lock`, enums | verify |
| Ruby 3.4 | CI runs 3.3.4 only, so it needs a 3.4 job | CI change |
| `json < 3.0` cap | drop it only after a no-lockfile install plus the `:db` suite are green on Rails 8.1 | verify |
| `spec/dummy` | regenerate for 0.32 (shakapacker.yml, `load_defaults 8.1`) | task |

### Host (civora-org/civora-host)

| Item | Finding |
|---|---|
| `layouts/decidim/header/_main_links_desktop.html.erb` | **must be re-based**: 0.32.1 restructured the file, and a pin bump alone would silently keep the stale 0.31.7 markup |
| `layouts/decidim/header/_main_search.html.erb` | upstream moved the submit button; re-base and check visually |
| `layouts/decidim/footer/_main_links.html.erb` | upstream is byte-identical between v0.31.7 and v0.32.1, so it stays valid |
| participation-link view copies (accountability `_project`, budgets `show`) | re-copy from the 0.32.1 gems; the existing drift test will flag them |
| `config/shakapacker.yml` | replace from the 0.32 template; drop `dev_server.https` |
| npm `@decidim/*`, `custom.js`, `tailwind.config.js` | move to 0.32 versions; webpack-dev-server 5.2.2 |
| `config.load_defaults` | 7.2 → 8.1 |
| `SECRET_KEY_BASE` | back up `SECRET_KEY_BASE` and `tmp/local_secret.txt`, then run `bin/rails decidim:upgrade:encryption` |
| SMTP | apply the `SMTP_STARTTLS_AUTO` fix |
| `.gitignore` | add `/public/sw.js*` |
| Dockerfile / CI | Ruby 3.4.7, libvips (`.ico` favicons are no longer supported, so check the org favicon); the CI ImageMagick step becomes libvips |
| Removed modules (collaborative drafts, sortitions) | not enabled in the host |

## 4. Gemspec changes

- `decidim-core` / `decidim-admin`: `"~> 0.31.5"` becomes `">= 0.31.5", "< 0.33"`. One engine release then serves both lines, and the host moves on its own timeline. Add a CI matrix of Decidim 0.31 on Ruby 3.3 and Decidim 0.32 on Ruby 3.4, and recommend `>= 0.32.1` to hosts.
- `required_ruby_version`: raise to `>= 3.3` for honesty.
- The `json < 3.0` cap stays until proven unnecessary (AGENTS.md lesson on fresh resolutions).
- Prune `.bundler-audit.yml` in both repos to graphql, rack-proxy and rubyzip, and re-run the auditor against a fresh resolution.

## 5. Recommended path

1. **Engine dual-support release (1.5–2.5 d):** widen the gemspec, add the CI matrix, regenerate the dummy app, sweep Rails 8.1 / Rack 3.2 deprecations, add a locale-URL check for the open-data, handoff and canonical links, and ship a minor release.
2. **Host branch on 0.32.1 (3–4 d):**
   - bump the Gemfile and run `decidim:upgrade`, `db:migrate`, `decidim:upgrade:encryption` and `data:migrate`;
   - apply the config edits;
   - re-base the header and search overrides and re-copy the participation-link views;
   - update npm, the Dockerfile (Ruby 3.4.7, libvips) and the favicon.
3. **Live verification (1–1.5 d)** on the Postgres stack:
   - `docker compose up`, the demo test plan, and computed styles;
   - locale URLs and redirects, a CRZ import run, PDF output, and `/up`;
   - a secret-key and encrypted-credential drill with a backup restore.
4. **Cleanup (0.5 d):** prune the bundler-audit ignores and the brakeman EOLRails ignore, update the README requirements and the "Customisations over Decidim" note, and tag the host.

The total is about 6–8.5 working days, plus 1–2 days of contingency.

## 6. Risks

- Locale-prefixed URLs may break shared links: open-data feeds, CRZ handoff and bookmarks.
- Secret-key and encryption migration mistakes are hard to undo, so the backup and restore drill is mandatory.
- A stale header override silently regresses login and navigation markup.
- Asset build: shakapacker 9.7 and the host's `custom.js`.
- If libvips is missing from the image, image processing fails at runtime, not at boot.
- graphql, rack-proxy and rubyzip (High) stay open.
- 0.32.1 is about 10 weeks old; check for 0.32.2 before go-live.
- Once 0.33 ships, staying on 0.31 means no upstream fixes at all.

## 7. Recommendation and trigger

- **Go:** upgrade before the first pilot goes live and before onboarding a second municipality. There is no production host yet, so no data migration or downtime cost. After pilot data exists, the secret-key and URL changes get riskier.
- **Start step 1 (engine) now:** it is low risk and backwards compatible.
- **Start steps 2–4** when the first of these happens: pilot hosting is booked, 0.32.2 ships, or 0.33.0 gets a date.
- **No-go:** lost locale redirects on open-data or CRZ links, or an unrecoverable encryption step. In that case stay on 0.31.7 with the documented ignores, time-boxed.
- **Do not wait for 0.33:** it has no date.

## 8. Proposed issues

- Engine (S/M): dual-line gemspec, Ruby 3.4 / Decidim 0.32 CI matrix, dummy app regeneration.
- Engine (S): locale-URL audit of the open-data, handoff and canonical links, with specs.
- Engine (S): Rack and Rails 8.1 deprecation sweep (`:unprocessable_content`).
- Host (M): bump to 0.32.1 (Gemfile, npm, shakapacker.yml, load_defaults, Dockerfile, libvips, SMTP, .gitignore).
- Host (S): re-base the header and search overrides and the participation-link copies, plus a regression check.
- Host (S/M): secret-key and encryption upgrade runbook and restore drill.
- Both (S): prune the bundler-audit and brakeman ignores; document the rubyzip mitigation.

## 9. Verify (not checked in this spike)

- Whether the patched devise release is 5.x.
- Whether json 3 works with ActiveSupport 8.1.
- Locale redirects for the engine's mounted routes.
- Dummy app generation on 0.32.
- The host asset build with shakapacker 9.7.
- The organization's favicon format.
