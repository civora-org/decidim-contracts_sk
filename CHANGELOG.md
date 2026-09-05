## [Unreleased]

## [0.17.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.16.0...v0.17.0) (2026-09-05)


### Features

* **admin:** add CRZ handoff PDF export (M02-05-C) ([3892fd9](https://github.com/civora-org/decidim-contracts_sk/commit/3892fd9eb1563978c8f0a203846327dfb6e4fabd))
* **amendments:** add amendment lifecycle and public version history (M02-05-B) ([98f4dd1](https://github.com/civora-org/decidim-contracts_sk/commit/98f4dd18c68e0b130728784b0f6b7d4feac02525))
* **documents:** add safe upload validation (M02-05-A) ([1e052a7](https://github.com/civora-org/decidim-contracts_sk/commit/1e052a749fc200363a775f338919b69efcd03a39))
* **testing:** add demo seed task, spec demo data and manual test scenarios ([81c89ca](https://github.com/civora-org/decidim-contracts_sk/commit/81c89cac86a847052321efc3d885fa8d4979b7af))


### Bug Fixes

* **testing:** satisfy Decidim organization/user validations in demo seed task ([842c424](https://github.com/civora-org/decidim-contracts_sk/commit/842c4249b482a3f52c9f8b6d9d9de4fc4b4cd23b))

## [0.16.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.15.0...v0.16.0) (2026-09-05)


### Features

* **catalogue:** add public contract detail page with parties and not-found handling (M02-04-C) ([bc3696c](https://github.com/civora-org/decidim-contracts_sk/commit/bc3696c810dbbe594f396a128be138ad50a3ecd4))
* **catalogue:** add public contracts index with published-only scope and empty state (M02-04-B) ([aa1234d](https://github.com/civora-org/decidim-contracts_sk/commit/aa1234de9b7e502bb0c430271d018dd680bf3cb8))
* **documents:** add document upload and storage wiring (M02-05-A0) ([e2b8535](https://github.com/civora-org/decidim-contracts_sk/commit/e2b8535d1cc866fe5978719e23abe496b279e20a))


### Bug Fixes

* **ci:** ignore upstream-blocked rubyzip advisory CVE-2026-85396 ([2dddd4b](https://github.com/civora-org/decidim-contracts_sk/commit/2dddd4b0385ac5711314ed3005fc24cb7507508e))
* **ci:** ignore upstream-blocked rubyzip advisory CVE-2026-85396 ([228bd31](https://github.com/civora-org/decidim-contracts_sk/commit/228bd31017f530be45b1f9c40814180d63b6290f))

## [0.15.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.14.0...v0.15.0) (2026-09-05)


### Features

* **admin:** add admin party management for contracts (M02-03-D) ([90505b3](https://github.com/civora-org/decidim-contracts_sk/commit/90505b3b97a8eb63bad3d76b51591253bcc40169))

## [0.14.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.13.0...v0.14.0) (2026-09-04)


### Features

* **models:** add contract content fields migration and admin form (M02-02-D) ([935ec76](https://github.com/civora-org/decidim-contracts_sk/commit/935ec76bb8d137d5fefc8c1ae78db0b7d19c0381))

## [0.13.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.12.0...v0.13.0) (2026-09-04)


### Features

* **admin:** add lifecycle transition actions with audit trail (M02-03-B) ([461ebcf](https://github.com/civora-org/decidim-contracts_sk/commit/461ebcf13496a2b5a0b80229499b846df4bc83f7))

## [0.12.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.11.0...v0.12.0) (2026-09-04)


### Features

* **admin:** add admin contracts CRUD with editor scope (M02-03-A) ([61b65cc](https://github.com/civora-org/decidim-contracts_sk/commit/61b65cc03f796fc45cfc4a5e00706f721814a184))

## [0.11.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.10.0...v0.11.0) (2026-09-03)


### Features

* **spec:** add stage-1 dummy harness and request specs (M02-04-A) ([4897999](https://github.com/civora-org/decidim-contracts_sk/commit/48979995f3b501d2ad128bb8885906641927477c))

## [0.10.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.9.0...v0.10.0) (2026-09-03)


### Features

* **models:** add amendment and audit event models and migrations (M02-02-C) ([de70118](https://github.com/civora-org/decidim-contracts_sk/commit/de70118733c3667469a6181b54a54e63ad1cb708))
* **models:** add party and document models and migrations (M02-02-B) ([9fd0345](https://github.com/civora-org/decidim-contracts_sk/commit/9fd034572462089457598c9da7c8d6739c503433))

## [0.9.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.8.0...v0.9.0) (2026-09-03)


### Features

* **models:** add contract model and migration (M02-02-A) ([6950004](https://github.com/civora-org/decidim-contracts_sk/commit/69500048f702280fb565b16e82c13c0db4c00e38))

## [0.8.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.7.0...v0.8.0) (2026-09-03)


### Features

* **permissions:** add config-based role resolver (M02-01-B) ([8c76d48](https://github.com/civora-org/decidim-contracts_sk/commit/8c76d4840b4cdcef6c1ae12bab50d0ad421b00d7))
* **permissions:** add table-driven Permissions class and controller wiring (M02-01-B) ([1d7b97f](https://github.com/civora-org/decidim-contracts_sk/commit/1d7b97f3075fdddbffe2c9995d93baf3ff068361))

## [0.7.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.6.1...v0.7.0) (2026-09-02)


### Features

* **lifecycle:** add contract lifecycle state machine and transition rules (M02-01-A) ([e219c17](https://github.com/civora-org/decidim-contracts_sk/commit/e219c175b9ed4532568a705deae33410d16e98ad))

## [0.6.1](https://github.com/civora-org/decidim-contracts_sk/compare/v0.6.0...v0.6.1) (2026-09-01)


### Bug Fixes

* **ci:** exhaustive per-advisory ignores for upstream-blocked CVEs (decidim 0.31.7 pins) ([0998070](https://github.com/civora-org/decidim-contracts_sk/commit/0998070a7e67b51e96ddf542e931045ac65f2257))
* **ci:** use bundler-audit 0.9 config format (.bundler-audit.yml, ignore key) ([57bb856](https://github.com/civora-org/decidim-contracts_sk/commit/57bb8562eaf6cfdd2d2ba13b576e2ce84a9bd709))
* **gemspec:** raise decidim floor to 0.31.5 (CVE-2026-45573) and sort dev deps ([7cbbc2f](https://github.com/civora-org/decidim-contracts_sk/commit/7cbbc2f13cec9c0181f3dc073d8238757322a6d5))

## [0.6.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.5.0...v0.6.0) (2026-09-01)


### Features

* **controllers:** add public catalogue scaffold with mount-root routes (M01-01-I/K) ([cc4c024](https://github.com/civora-org/decidim-contracts_sk/commit/cc4c024e1e87f6739334b75d37cb865210b649f3))
* **gemspec:** target Decidim 0.31 instead of 0.28 (M01-01-I/K) ([889e71d](https://github.com/civora-org/decidim-contracts_sk/commit/889e71d49e08706db2264538a4bd2e8d3b99f8c4))

## [0.5.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.4.1...v0.5.0) (2026-08-31)


### Features

* **locales:** add public catalogue keys and locale-contract specs (M01-01-G) ([7fb0f5d](https://github.com/civora-org/decidim-contracts_sk/commit/7fb0f5dcb7414c077a80e20448230e908cebcbe8))

## [0.4.1](https://github.com/civora-org/decidim-contracts_sk/compare/v0.4.0...v0.4.1) (2026-08-31)


### Bug Fixes

* **admin:** harden admin base authorization ([916ecb4](https://github.com/civora-org/decidim-contracts_sk/commit/916ecb46d8704f1a5988d934876fe067034813de))
* **admin:** inherit Decidim admin base for admin-level authorization ([7a0ef46](https://github.com/civora-org/decidim-contracts_sk/commit/7a0ef46bcf6a1b7be48d369eacd08e73abf1c070))

## [0.4.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.3.0...v0.4.0) (2026-08-31)


### Features

* **models:** add abstract base model with table prefix (M01-01-E) ([7bad8f1](https://github.com/civora-org/decidim-contracts_sk/commit/7bad8f13862bfa5b60ed6cb6926964536ea19a89))

## [0.3.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.2.0...v0.3.0) (2026-08-31)


### Features

* **controllers:** add base application controller and helper (M01-01-D) ([9a1a869](https://github.com/civora-org/decidim-contracts_sk/commit/9a1a8696df7da0bf2105bc4bf28b83f8cf6184e8))

## [0.2.0](https://github.com/civora-org/decidim-contracts_sk/compare/v0.1.0...v0.2.0) (2026-08-30)


### Features

* configure engine with locales and routes (M01-01-B) ([233b116](https://github.com/civora-org/decidim-contracts_sk/commit/233b116b9de2f8ad5f11b800db3b5a04673c95d4))
* configure engine with locales and routes (M01-01-B) ([36a7728](https://github.com/civora-org/decidim-contracts_sk/commit/36a7728844b36164eb3ac75181327e37bed4d82f)), closes [#34](https://github.com/civora-org/decidim-contracts_sk/issues/34)
* **gemspec:** add Decidim runtime and dev dependencies (M01-01-C) ([6c6d465](https://github.com/civora-org/decidim-contracts_sk/commit/6c6d465b921113baf06755ce13bcfe19152b1da3))


### Bug Fixes

* add Style/Documentation comment to Engine class ([1f0169d](https://github.com/civora-org/decidim-contracts_sk/commit/1f0169de015c894dcdfc33610cee3a64cf886a66))
* **gemspec:** bump decidim deps to ~&gt; 0.28 with Ruby 3.3 compat ([126aed5](https://github.com/civora-org/decidim-contracts_sk/commit/126aed5923d2c4aff6009f446bbce5773d33ac76))
* guard engine require behind Rails constant ([11dd940](https://github.com/civora-org/decidim-contracts_sk/commit/11dd94095474bbf80a24fe4f075a024cb39bd83a))
* **spec:** remove bundle gem placeholder test ([db8e286](https://github.com/civora-org/decidim-contracts_sk/commit/db8e2868cd687ca12914ef9341de0bc0190f623c))

## [0.1.0] - 2026-08-30

- Initial release
