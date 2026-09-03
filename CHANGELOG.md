## [Unreleased]

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
