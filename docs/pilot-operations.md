# Pilotná prevádzka — operačný runbook (epic #15)

> Kompletný, copy-paste spustiteľný runbook pre pilota: inštalácia stagingu a
> produkcie na čerstvom slovenskom VPS, deploy procedúra, nácvik migrácie a
> rollbacku, zálohy a nácvik obnovy, monitoring, akceptačný checklist, feedback
> proces a release notes proces. Napísané pre sólového správcu — každý krok je
> vykonateľný doslova. Text po slovensky, príkazy po anglicky.
>
> **Rozsah a hranice:** `decidim-contracts_sk` je engine, nie samostatná
> aplikácia. Pilot beží v **hostiteľskej Rails aplikácii s Decidim 0.31.x**
> (mount na `/zmluvy`). Engine neposkytuje: vlastný health endpoint, ActiveStorage
> schému (tabuľky ActiveStorage má na starosti hostiteľská app), background
> jobs (žiadne nemá — pozri § 1) ani Decidim inštaláciu. Všetko, čo je teritóriom
> hostiteľa, je v tomto dokumente explicitne označené.

---

## 1. Architektúra pilota

| Komponent | Voľba | Poznámka |
|---|---|---|
| Produkčný VPS | WebSupport alebo Slovanet, 2 vCPU / 4 GB RAM / 50 GB SSD, Ubuntu 24.04 | dáta v SR — kľúčový predajný argument ([gtm-pilot-plan § 2](https://github.com/civora-org/civora-platform/blob/main/docs/06-sales/gtm-pilot-plan.sk.md), civora-platform) |
| Staging VPS | rovnaký poskytovateľ, menší (2 vCPU / 2 GB RAM) | rovnaký OS a stack ako produkcia, iná doména |
| Databáza | PostgreSQL 16 (apt, `pgdg` nie je potrebný — Ubuntu 24.04 má 16) | lokálne na každom VPS |
| App server | Puma (systemd unit) | cez UNIX socket |
| Reverse proxy | Caddy | auto-HTTPS (Let's Encrypt), servuje aj statické `/assets` |
| Súbory | ActiveStorage `local` service na disk + off-site záloha adresára | engine `has_one_attached :file` na `Document`; schému ActiveStorage vlastní host app |
| Background jobs | **žiadne** | engine nevie `ApplicationJob`/`ActiveJob` a nedefinuje `app/jobs` — CRZ import je rake task (`decidim_contracts_sk:crz_import:sync`) schedulovaný cron-om; **sidekiq sa nainštalovať nemusí** |
| Monitoring | UptimeRobot + týždenná prehľada logov; vlastník = maintainer | detail § 7; Prometheus/Grafana neskôr (epic #16) |
| Zálohy | nočný `pg_dump -Fc` + `tar` storage adresára; 7 dní lokálne + 30 dní off-site (rclone → S3-compatible, napr. Exoscale SOS) | skripty `bin/backup` / `bin/restore` v tomto repozitári (šablóny pre host server) |

Dva stroje, nič viac. Žiadny kontajner, žiadny orchestrátor, žiadna správa
sekretov mimo Rails credentials — sólový maintainer musí dokázať celý stack
reprodukcovať z tohto dokumentu.

## 2. Prvá inštalácia (staging a produkcia)

Kroky sú identické pre oba servery; líšia sa len názvom domény a priebežne
aj obsahom databázy. Robiť v tomto poradí.

### 2.1 Systémový používateľ a balíčky

```bash
sudo adduser --disabled-password --gecos "Deploy" deploy
sudo usermod -aG sudo deploy
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential git curl libssl-dev libreadline-dev zlib1g-dev \
  libpq-dev postgresql postgresql-contrib libyaml-dev pkg-config \
  libjpeg-dev libvips imagemagick caddy
sudo systemctl enable --now postgresql caddy
```

### 2.2 Ruby 3.3 (rbenv)

```bash
sudo -iu deploy
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.profile
echo 'eval "$(rbenv init -)"' >> ~/.profile
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
exec $SHELL
rbenv install 3.3.4 && rbenv global 3.3.4
gem install bundler
```

(3.3.4 je verzia, ktorú lúčuje CI tohto repozitára; engine vyžaduje Ruby ≥ 3.2
a Decidim 0.31 podporuje 3.3 — overené proti nainštalovanému 0.31.7 gemsetu,
pozri gemspec.)

### 2.3 PostgreSQL

```bash
sudo -iu postgres createdb contracts_sk_production
sudo -iu postgres psql -c "CREATE ROLE contracts_sk LOGIN PASSWORD '<generate-via-openssl-rand-hex-24>';"
sudo -iu postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE contracts_sk_production TO contracts_sk;"
```

Na stagingi rovnako s `contracts_sk_staging`. Databázu **nikdy** neinitujeme
`schema:load` na produkcii — schéma vzniká výhradne migráciami (§ 4).

### 2.4 SSH prístup

Na spravovacom stroji: `ssh-keygen -t ed25519`, verejný kľúč doplniť na VPS do
`/home/deploy/.ssh/authorized_keys`; v `sshd_config` nechať len
`PasswordAuthentication no`. Deploy reposity stiahne cez read-only deploy key
(GitHub → repo → Settings → Deploy keys) alebo HTTPS token.

### 2.5 Hostiteľská Rails app a engine

Hostiteľskú Decidim 0.31 app vytvor a nakonfiguruj podľa README tohto
repozitára (Gemfile → `bundle install` → mount `Decidim::ContractsSk::Engine,
at: "/zmluvy"` v `config/routes.rb`). Engine pridáva menu položky aj admin
sidebar sám; konfigurácia rolí je cez `Decidim::ContractsSk.role_resolver`
(pozri README § Configuration).

### 2.6 Secrets a prostredie

```bash
cd /var/www/contracts_sk   # práca v produkcii
bin/rails secret           # → SECRET_KEY_BASE
EDITOR=vim bin/rails credentials:edit
```

Do credentials ulož `master_key` drž len na serveri (`config/master.key` nikdy
nekomituj, zálohuj off-site spolu s root heslami — bez neho sa credentials
nedajú otvoriť). Minimálne ENV premenné systemd unitu (§ 2.7):

```ini
RAILS_ENV=production
SECRET_KEY_BASE=<value>
DATABASE_URL=postgres://contracts_sk:<password>@localhost:5432/contracts_sk_production
RAILS_LOG_TO_STDOUT=1
```

`RAILS_SERVE_STATIC_FILES` **nepoužívame** — statické súbory servuje Caddy
(§ 2.9). Ak host app nemá ActiveStorage schému ešte nasadzovanú:
`bin/rails db:migrate` ju vytvorí spolu s migráciami enginu (host teritórium —
engine žiadnu storage migráciu nedodáva, zámerne).

### 2.7 systemd unit — Puma

Bez sidekiq (engine nemá žiadne background jobs — pozri § 1). Cron-om
schedulované rake tasky majú vlastné timer-y (§ 5, § 6).

`/etc/systemd/system/contracts_sk.service`:

```ini
[Unit]
Description=Contracts SK (Puma)
After=network.target postgresql.service

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/contracts_sk
EnvironmentFile=/etc/contracts_sk/env
ExecStart=/home/deploy/.rbenv/shims/bundle exec puma -C config/puma.rb
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now contracts_sk
```

### 2.8 Seed demo dát (iba staging)

```bash
bin/rails "decidim_contracts_sk:seed_demo[<organization_id>]"
```

Task je idempotentný a vieťe každý lifecycle stav plus CRZ-mirror demo záznamy
(scenáre: docs/manual-test-scenarios.md). **Na produkcii nespúšťať.**

### 2.9 Caddyfile

Caddy servuje `/assets/*` priamo z `public/assets` (po `assets:precompile`) a
ostatné proxy-uje na Puma UNIX socket:

```
zmluvy.example.sk {
    encode gzip
    route /assets/* {
        file_server {
            root /var/www/contracts_sk/public
        }
    }
    reverse_proxy unix//run/puma/contracts_sk.sock
}
```

V `config/puma.rb` bind na ten istý socket:

```ruby
bind "unix:///run/puma/contracts_sk.sock"
```

Caddy sám si vystará a obnoví certifikát (auto-HTTPS). Overenie:

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://zmluvy.example.sk/zmluvy/   # 200
```

## 3. Deploy procedúra

Jednoduchý git-based deploy; všetko pod `deploy` užívateľom. Script
`bin/deploy` (v host app; tu je verzia na skopírovanie):

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /var/www/contracts_sk
git fetch --all
git reset --hard origin/main
bundle install --deployment --jobs 4
bin/rails db:migrate
bin/rails assets:precompile
sudo systemctl restart contracts_sk
# Smoke check — verejný katalóg musí odpovedať 200:
sleep 3
code=$(curl -s -o /dev/null -w "%{http_code}" https://zmluvy.example.sk/zmluvy/)
[ "$code" = "200" ] || { echo "Smoke check FAILED (HTTP $code) — rolling restart again or investigate"; exit 1; }
echo "Deploy OK"
```

Pravidlá:

- **Engine migrácie sú aditívne a reverzibilné.** Všetkých 12 migrácií v
  `db/migrate/` je štandardne reverzibilných (`def change` / `def down` /
  `reversible` bloky) — tvorba tabuliek, pridávanie stĺpcov a indexov; nič
  nedestruije existujúce dáta. Reverzibilita je disciplína pinutá v
  migráciových špecifikáciách a overovaná nácvikom (§ 4).
- **Nikdy `db:schema:load` na produkcii.** Schéma vzniká len migráciami.
- Deploy vždy najprv na staging (§ 4), produkcia až po prejdení akceptačného
  checklistu (§ 8).
- Ak deploy zlyhá na `db:migrate`, ne rollback-ovať produkciu násilne — pozri
  advisory v § 4 a skutočný rollback cesta je restore zo zálohy (§ 6).

## 4. Rehearsal: migrácia a rollback (staging, pred každým prod deploym)

Cvičenie dokazuje, že migrácie sú schémovo reverzibilné. Spúšťať pred **každým**
produkčným deployom, ktorý obsahuje novú migráciu.

```bash
# 1. Produkčný dump na staging (alebo posledný nightly backup):
scp production:/var/backups/contracts_sk/latest.dump /tmp/
sudo -iu postgres dropdb --if-exists contracts_sk_rehearsal
sudo -iu postgres createdb contracts_sk_rehearsal
sudo -iu postgres pg_restore -d contracts_sk_rehearsal /tmp/latest.dump

# 2. App pusti proti rehearsal DB a zmigruj:
DATABASE_URL=postgres://contracts_sk:<pw>@localhost:5432/contracts_sk_rehearsal \
  bin/rails db:migrate

# 3. Test suite (aspoň :db skupiny) proti rovnakej DB:
DATABASE_URL=postgres://contracts_sk:<pw>@localhost:5432/contracts_sk_rehearsal \
  CONTRACTS_SK_DB=1 bundle exec rspec

# 4. Rollback a re-migrácia — dôkaz reverzibility:
DATABASE_URL=postgres://contracts_sk:<pw>@localhost:5432/contracts_sk_rehearsal \
  bin/rails db:rollback STEP=<n>        # n = počet nových migrácií v deployi
DATABASE_URL=postgres://contracts_sk:<pw>@localhost:5432/contracts_sk_rehearsal \
  bin/rails db:migrate
```

Pass kritérium: `db:rollback STEP=n` prebehne bez chyby a `db:migrate`
obnoví identickú schému (`pg_dump --schema-only` diff prázdny).

> **Advisory:** rollback je **schémová** bezpečnosť, nie dátová stratégia.
> Rollback dátovo-nosnej migrácie je bezpečný len kým užívatelia do nových
> stĺpcov nič nezapísali (inak dáta padajú). Skutočný produkčný rollback je
> **restore zo zálohy** (§ 6) — `db:rollback` na produkcii nepoužívať na
> „vrátenie dát“.

## 5. Zálohy

Nočne: `pg_dump -Fc` databázy + `tar` adresára ActiveStorage storage.
Retencia: **7 dní lokálne + 30 dní off-site** (rclone → S3-compatible, napr.
Exoscale SOS vo Viedni — EÚ; pre pilota akceptovateľné, produkčne preferuj
SK/EÚ endpoint).

Hotové šablóny v tomto repozitári: [`bin/backup`](../bin/backup) a
[`bin/restore`](../bin/restore) — engine-agnostické (čisto env-vars:
`DATABASE_URL`, `STORAGE_PATH`, `BACKUP_DIR`, `RCLONE_REMOTE`), s hlavičkou
označujúcou, že sú to pilotné šablóny pre **host server**, nie súčasť test
suite enginu. Inštalácia:

```bash
sudo install -m 0755 bin/backup /usr/local/bin/contracts-backup
sudo install -m 0755 bin/restore /usr/local/bin/contracts-restore
sudo mkdir -p /var/backups/contracts_sk && sudo chown deploy:deploy /var/backups/contracts_sk
```

systemd timer (preferovaný pred cron-om — logy a závislosti v journalctl):

`/etc/systemd/system/contracts-backup.service`:

```ini
[Unit]
Description=Contracts SK nightly backup

[Service]
Type=oneshot
User=deploy
EnvironmentFile=/etc/contracts_sk/env
Environment=STORAGE_PATH=/var/www/contracts_sk/storage
Environment=BACKUP_DIR=/var/backups/contracts_sk
Environment=RCLONE_REMOTE=sos:contracts-sk-backups
ExecStart=/usr/local/bin/contracts-backup
```

`/etc/systemd/system/contracts-backup.timer`:

```ini
[Unit]
Description=Nightly contracts backup

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now contracts-backup.timer
```

Rovnako ( vlastný timer) scheduluj CRZ import — engine žiadny scheduler
neposkytuje, host musí:

```ini
OnCalendar=*-*-* 03:30:00
# ExecStart: bin/rails "decidim_contracts_sk:crz_import:sync[<organization_id>,<SINCE ISO8601>]"
```

Prvá synchronizácia: SINCE = go-live timestamp; ďalšie noci SINCE = start
predošlého behu (task exitne non-zero pri nedostupnom zdroji — timer failure
vidno v `systemctl list-timers` / monitoring).

## 6. Rehearsal: obnova zo zálohy

**Cieľ:** RTO < 1 h (od zistenia výpadku po funkčnú app), RPO < 24 h (max.
strata = jeden nočný cyklus). Nácvik spustiť **raz pred go-live a potom
kvartálne** — výsledok zapísať do[pilot-feedback-log.md](pilot-feedback-log.md)
(stĺpec typ = `drill`).

Postup — na stagingu, vždy do **scratch DB** (nikdy nie cez produkčnú):

```bash
# 1. Zober posledný off-site backup:
rclone copy sos:contracts-sk-backups/db/latest.dump /tmp/drill/
rclone copy sos:contracts-sk-backups/storage/latest.tgz /tmp/drill/

# 2. Obnov DB do scratch databázy (skript robí presne toto):
BACKUP_FILE=/tmp/drill/latest.dump \
DATABASE_URL=postgres://contracts_sk:<pw>@localhost:5432/contracts_sk_drill \
  /usr/local/bin/contracts-restore

# 3. Rozbehaj app proti drill DB a prejdi akceptačný checklist (§ 8):
DATABASE_URL=postgres://contracts_sk:<pw>@localhost:5432/contracts_sk_drill \
  RAILS_ENV=production bin/rails s -b 127.0.0.1 -p 3000
```

Meranie: čas od začiatku kroku 1 po úspešný smoke check (`curl` 200 na
`/zmluvy/` + jeden admin login) = pozorované RTO. Rozdiel času poslednej
transakcie v zálohe vs. okamih simulovaného výpadku = RPO. Zapísať do logu;
ak RTO > 1 h, skript/infra optimalizovať a cvičenie opakovať.

## 7. Monitoring a vlastníctvo

- **Vlastník:** maintainer (sólo prevádzka — žiadna rota; ak maintainer
  nedostupný, piltná obec má eskalačný kontakt v ZOÜ).
- **Stack:** UptimeRobot (5-min interval) na zdravotný endpoint + týždenná
  ručná prehľada logov (10 min v piatok: `journalctl -u contracts_sk --since -7d
  -p warning`, `systemctl list-timers`, posledný backup timestamp).
- **Health endpoint:** engine **žiadny neposkytuje** (`config/routes.rb`
  neobsahuje žiadnu `up`/`health` route — verejný root je katalóg). Ak host
  app beží na Rails 8+, má `/up` zabudovaný; na Rails 7.2 (Decidim 0.31) pridaj
  v host app zdravotný controller, napr. route `get "/up", to: "health#show"`
  vrátiaci 200 po `SELECT 1` against DB. Monitore `/up` (host root), nie
  `/zmluvy/` — engine route nekontroluje DB.
- **Čo znamenajú alerty a prvá reakcia:**

| Alert | Význam | Prvá reakcia |
|---|---|---|
| UptimeRobot down > 10 min | app alebo proxy nedostupná | `ssh` → `systemctl status contracts_sk caddy`, `journalctl -u contracts_sk -n 100`; restart unitu; ak padá opakovane — rollback na predošlý release (`git reset --hard <prev-tag>` + restart) |
| Timer `contracts-backup` failed | záloha neprebehla — **vysoká priorita**, ohrozuje RPO | spustiť ručne, čítať chybu (disk full / rclone auth / DB prístup); do opravy ne deployovať nič dátové |
| Timer `crz_import` failed | ekosystem nedostupný alebo sa zmenila schéma | nie je urgentné (mirror je staleness-safe); pozri docs/crz-import.md § Failure modes; zopakujú ďalšiu noc |
| Disk > 85 % | rast logov/storage/backups | prune starých backupov lokálne, rotuj logy, zväčši disk |

Prometheus/Grafana a alerting-škálovanie vlastní epic #16 — tu zámerne len
minimálna pilotná výbava.

## 8. Staging akceptačný checklist

Prejdi na stagingu po každom deploye pred prod push-om (a pri každom
restore-drilli v § 6). Založené na docs/manual-test-scenarios.md a
docs/qa-checklist.md; demo dáta seed-neš podľa § 2.8.

### Základ a životný cyklus

- [ ] Pilot má aspoň **2 osoby** s rolami enginu (odosielateľ ≠ posudzovateľ; pri predvolenom resolveri 2 org adminov s prijatými admin podmienkami), alebo je v initializeri vedome nastavené `Decidim::ContractsSk.allow_self_review = true` — **pass:** pravidlo štyroch očí (#123).
- [ ] Osoba, ktorá urobila `submit` (demo: `contracts-editor@example.org`), na riadku záznamu nevidí tlačidlá `approve` / `return` / `reject`; priamy POST na tieto akcie je zamietnutý; druhý admin (demo: `contracts-admin@example.org`) ich vidí a `approve` prejde — **pass:** #123.

- [ ] Lehota CRZ (#124): admin index má stĺpec „Lehota CRZ"; na demo dátach má DEMO-2026-003 oranžový štítok „7 dní" (po novom seede), DEMO-2026-002 a -004 červený „Po termíne", DEMO-2026-001 tlmenú pomlčku (neznámy dátum podpisu), mirror/zamietnuté/archivované záznamy a DEMO-2026-006 žiadny (publikované redakčné záznamy sa sledujú; DEMO-2026-006 nemá štítok len preto, že je potvrdený ako zverejnený v CRZ (`crz_filed_at`, #125)); čipy „CRZ po termíne" / „CRZ do 14 dní" majú správne počty a filter `?deadline=overdue` / `?deadline=due_soon` zúži zoznam; edit DEMO-2026-003 ukazuje riadok s lehotou — **pass:** #124 (pomôcka, nie právne poradenstvo; štítky starnú, na obnovu spusti seed znova).

- [ ] `GET /zmluvy/` → 200; vidno publikované demo záznamy (DEMO-2026-006, 008, 009 a 24 štatistických DEMO-2026-010..033) — **pass:** 27 kariet na dvoch stránkach, lokalizované.
- [ ] Prihlásenie adminom; `GET /zmluvy/admin/contracts` bez prihlásenia → redirect na sign-in — **pass:** A1.
- [ ] Vytvor záznam (title + reference) → stav `draft` — **pass:** A3.
- [ ] Uprav DEMO-2026-001: state/author/organization nie sú form-writable — **pass:** A4.
- [ ] Uprav DEMO-2026-006 (published) → update zamietnutý — **pass:** A5.
- [ ] `submit` na DEMO-2026-001 → `in_review` + audit event (ďalšie kroky `return`/`approve` na tomto zázname robí **iný** admin ako ten, kto urobil `submit`) — **pass:** A6.
- [ ] `return` s povinným dôvodom na DEMO-2026-002 → `returned`; dôvod vidno v "Reviewer decision" baneri na edit stránke; `submit` znova → `in_review` a baner zmizne — **pass:** #90 cesta.
- [ ] `approve` DEMO-2026-002 → `approved` — **pass:** A7 (seed zapisuje stavy priamo bez odosielateľa, takže ho zvládne aj jediný demo admin; po `submit` cez UI už `approve` musí urobiť iný admin).
- [ ] Publikácia bez redakčného stampu (DEMO-2026-001 po approve druhým adminom) → zamietnutá špecifickým flashom; confirm na edit stránke (checkbox) → stamp; publikácia teraz úspešná — **pass:** redakčná brána ADR-007.
- [ ] `archive` na DEMO-2026-006 → `archived`, stále verejne vidno — **pass:** A9.
- [ ] Zopakuj ľubovoľný transition POST druhýkrát → zamietnutý — **pass:** A10 (concurrency guard).
- [ ] `reject` na jednom draftovom zázname cez curl bez rolí → zamietnutý — **pass:** permissions fail-closed.

### Dokumenty, CRZ handoff, CRZ import

- [ ] Attach / replace / remove dokumentu na DEMO-2026-001; > 10 MB alebo nepovolený content-type → chyba, nič sa neuloží — **pass:** A13 + QA checklist.
- [ ] `POST .../crz_handoff` na DEMO-2026-001 → PDF vygenerované; download funguje v ľubovoľnom stave; PDF je označené ako pomôcka, nie publikácia — **pass:** A14/A15.
- [ ] Admin index: `import_crz` form → platné CRZ id → záznam `published` s provenance; neexistujúce id → lokalizovaný flash — **pass:** docs/crz-import.md.

### Strany, amendments, audit

- [ ] Pridaj/edituj/odstráň strany na DEMO-2026-001; dve strany s rovnakou rolou legálne; na published → zamietnuté — **pass:** A11/A12.
- [ ] Vytvor amendment na DEMO-2026-006 (published), publish draft → frozen snapshot v verejnej verzii histórie na detail stránke; live polia ostávajú aktuálne — **pass:** ADR-006 cesta.
- [ ] `/zmluvy/admin/audit_events` → novšie prvé, filtre cez `?contract_id=` fungujú; záznamy o transitions, redakcii, amendmente a importe — **pass:** #92.

### Verejný katalóg a lokalizácia

- [ ] Detail DEMO-2026-006: obsahové polia, strany, downloady, verzie — **pass:** P3/P8.
- [ ] 404 matica: draft / in_review / returned / approved / rejected / archived / cudzia organizácia (DEMO-OTHER-001) / neexistujúce id — všetky rovnako 404 — **pass:** P4–P7.
- [ ] Provenance: DEMO-2026-008 (fresh) bez stale riadku; DEMO-2026-009 so stale riadkom; badge aj na indexe — **pass:** P9–P11.
- [ ] Prepnú locale na `sk`: katalóg, detaily, admin stavy/tlačidlá, provenance, audit — všetko slovensky — **pass:** P13.
- [ ] Health/smoke: `curl -s -o /dev/null -w "%{http_code}\n" https://<staging>/up` → 200 (ak host endpoint existuje).

## 9. Pilotný feedback proces

- **Kadencia:** týždenný 15-minútový call s pilotnou obcou (fixný termín).
- **Agenda (5 pevných otázok):**
  1. Čo ste tento týždeň v systéme robili? (používanie)
  2. Kde ste uviazli alebo čo vás spomalilo? (bugy/friction)
  3. Čo vám chýba na to, aby ste zmluvy viedli len tu? (feature requests)
  4. Čo by ste odporúčali kolegovi z obeckej radnice? (hodnota/referencia)
  5. Súhlas so zverejnením citátu/použitia ako referencie? (praise)
- **Záznam:** každý call → riadok (riadky) v [docs/pilot-feedback-log.md](pilot-feedback-log.md) (dátum, obec, zdroj, typ, popis, stav, issue link).
- **Triage pravidlo:**
  - **bug** → GitHub issue v `civora-org/civora-platform` (repo konvencia — issues nie sú v engine repozitári), stav v logu = `issue`;
  - **požiadavka** → triage do epicu #13 (doména) alebo #71 (importy), stav = `triaged`;
  - **pochvala** → uložiť ako referenčnú citáciu (so súhlasom z otázky 5), stav = `praise`.
- Log revidovať na začiatku každého callu (stav `open` → čo sa vybavilo).

## 10. Release notes proces

- **CHANGELOG.md vlastní release-please** — nikdy ručne neupravovať (repo konvencia). Release vzniká: tag/conventional-commit flow → release-please otvorí Release PR → merge → vznikne GitHub Release.
- **Pri každom release (checklist):**
  1. Skontrolovať, že Release PR je kompletný (semantic version, changelog z commitov).
  2. **Docs drift check:** README status bullets a sekcie Usage odrážajú nové funkcie (pre_FILL: ak nová funkcia, pridať bullet); docs/*.md nezostali pozadu.
  3. Po mergi: poslať pilotnej obci oznámenie s **výťahom z changelogu** (nie celý súbor) — 3–5 odrážok, čo sa zmenilo a čo ich to naučí; odkaz na verejný changelog.
  4. Deploy novú verziu na staging, prejdi § 8 checklist, až potom produkcia (§ 3).
- Pilotná komunikácia nesľubuje termíny — každá požiadavka končí v logu (§ 9), nie v terms.

---

*Súvisiace: [manual-test-scenarios.md](manual-test-scenarios.md) (zdroj checklistu § 8), [qa-checklist.md](qa-checklist.md), [crz-import.md](crz-import.md) (import operatíva), [gtm-pilot-plan.sk.md](https://github.com/civora-org/civora-platform/blob/main/docs/06-sales/gtm-pilot-plan.sk.md) § 6 (civora-platform) (čo ešte zostáva), epic #15 (tento dokument), epic #16 (monitoring škálovanie).*
