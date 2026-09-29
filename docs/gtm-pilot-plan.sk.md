# Civora Contracts SK — plán uvedenia na trh (pilot → predaj)

> Краткое резюме (RU): этот документ — пошаговый план вывода продукта на словацкий рынок: хостинг, пилот у муниципалитета, легальные требования, ценообразование и цикл продажи. Продукт — движок Decidim для работы с публичными контрактами (workflow + каталог), готовый к демонстрации (v1.2.0).

---

## 1. Produkt a hodnota (čo predávame)

**Pre koho:** slovenské obce, mestá a VŠI (verejne prospešné inštitúcie), ktoré dnes riešia zmluvy v tabuľkách, e-mailoch a zdieľaných dokladoch.

**Hodnota:**
- poriadok v životnom cykle zmluvy (draft → posúdenie → publikácia → archív) s rolami editor/recenzent;
- auditná stopa a ochrana osobných údajov (redakčná brána pred publikáciou);
- verejný katalóg zmlúv — transparentnosť bez budovania vlastného webu;
- import z CRZ (ekosystem.slovensko.digital) — záznamy sa dopĺňajú automaticky.

**Pozícia:** „workflow vrstva nad zmluvami", nie náhrada CRZ. To je dôležité pri predaji — nepredstierame registratívnu funkciu.

## 2. Hosting (odporúčania)

Kritérium č. 1 pre slovenský verejný sektor: **dáta v EÚ/na Slovensku + GDPR**.

| Možnosť | Lokalita | Cena (orientačne) | Poznámka |
|---|---|---|---|
| **WebSupport (VPS)** | Bratislava, SK | 20–50 €/mes | slovenský poskytovateľ, ľahký predaj argument „dáta v SR" |
| **Slovanet** | Bratislava, SK | 30–60 €/mes | B2B/VŠ tradične; možná zmluva SLA |
| **Exoscale** | Viedeň/Praha (EÚ) | 25–40 €/mes | jednoduchý API, kvalitný; nie SK dátové centrum |
| **Hetzner Cloud** | Nemecko/Fínsko (EÚ) | 10–25 €/mes | najlacnejšie; „EÚ, ale nie SR" — slabší predajný argument |
| **Scaleway** | Paríž/Amsterdam | 15–30 €/mes | alternatíva |

**Odporúčanie pre pilota:** WebSupport alebo Slovanet VPS (2 vCPU / 4 GB RAM / 50 GB SSD, ~30 €/mes) — PostgreSQL 16 + Ruby 3.3 + Reverse proxy (Caddy/Nginx) + zálohy mimo servera. Staging = rovnaký menší VPS.

**Technický stack pilotného servera:**
- hostiteľská Rails app s Decidim 0.31 + `decidim-contracts_sk` mountnutý na `/zmluvy`;
- HTTPS cez Let's Encrypt; zálohy: denný `pg_dump` + off-site (S3-compatible, napr. Exoscale SOS);
- monitoring: jednoducho — UptimeRobot (dostupnosť) + `healthz` endpoint a logwatch; neskoršie Prometheus/Grafana keď príde mierka (epic #16).

## 3. Legálne a compliance kroky (SK)

1. **GDPR:** zmluva o spracovaní údajov (ZoOU) s obcou; register spracovaní; šablónu DPA pripraviť vopred.
2. **ISVS:** ak systém používa štátna správa, zvaž registráciu v ISVS (katalóg IS VS) — pre obec to uľahčuje obstarávanie.
3. **Obstarávanie:** pilota podlimitne (do 1 000 € bez DPH — § 8 ZVO) priamo; nad limit → súpiska/CGP. Cena pilota nastaviť podľa toho.
4. **eIDAS/podpisy:** mimo rozsahu V0 — zmluvy sa do systému *zapisujú*, nepodpisujú. Toto povedať jasne na demo.
5. **Zodpovednosť za dáta:** CRZ mirror je len metadáta zverejnené štátom; editoriálne záznamy obstaráva obec.

## 4. Cenotvorba (návrh)

| Model | Cena | Kedy |
|---|---|---|
| Pilot (3 mesiace) | 0–500 € jednorázovo (nastavenie) | prvý referenčný zákazník |
| Prevádzka SaaS | 99–199 €/mes/obec | štandard po pilote |
| Inštalácia na vlastný server obce | 2 000–5 000 € jednorázovo + ročná podpora 20 % | väčšie mestá s IT oddelením |

Začať lacno: cieľom pilota je **referencia**, nie zisk.

## 5. E2E predajný proces (kroky)

1. **Príprava (1 týždeň):** demo inštancia na verejnej URL so seed dátami (`decidim_contracts_sk:demo:seed`), 1-stranový list (SK), cenová ponuka šablóna, ZOÜ šablóna.
2. **Terčovanie (1 týždeň):** zoznam 20–30 miest/obcí s aktívnou transparentnostnou agendou (mestá s open-data portálmi, ako Bratislava, Košice, Banská Bystrica + nadšenci ako Slovensko.Digital komunita). Nájsť meno: primátor/vedúca kancelárie/hovorca.
3. **Prvý kontakt:** krátky e-mail (5 viet) + link na demo. Druhá vlna: LinkedIn/telefonát kancelárii.
4. **Demo (30 min):** kliknúť scenáre z `docs/manual-test-scenarios.md` — životný cyklus zmluvy, auditná stopa, verejný katalóg. Ukázať CRZ import naživo (pôsobí najviac).
5. **Pilotná ponuka:** 3-mesačný pilot, 1 obec, 3–5 používateľov, cena symbolická, ukončenie kedykoľvek. Merateľný cieľ: „X zmlúv v katalógu do 90 dní".
6. **Pilotná prevádzka:** onboarding call, import ich skutočných zverejnených zmlúv z CRZ, týždenná spätná väzba (epic #15 — feedback proces).
7. **Konverzia:** po 90 dňoch — vyhodnotenie (počet zmlúv, čas úspor), ponuka prevádzky. Referencia + citácia primátora.
8. **Škálovanie:** každá referencia → 5 ďalších obcí v regióne; zváž partnerstvo v ekosystéme Slovensko.Digital.

**Metriky pilota na predaj:** počet zverejnených zmlúv, čas od draftu po publikáciu, počet oslovených obcí → demo → pilot konverzia.

## 6. Čo treba dokončiť pred prvým plateným zákazníkom

- [x] staging + produkčný deploy runbook (epic #15) — migrácie/rollback; § 3 → [pilot-operations.md](pilot-operations.md) § 3–4
- [x] záloha + obnova (rehearsal) — postup + skripty pripravené → [pilot-operations.md](pilot-operations.md) § 5–6 (`bin/backup`, `bin/restore`)
  - [ ] rehearsal raz prebehnúť naživo (vyžaduje reálny host server)
- [ ] monitoring vlastník + alerting (epic #16) — pilotné minimum definované → [pilot-operations.md](pilot-operations.md) § 7
- [x] pilotný feedback proces (týždenný 15-min call) → [pilot-operations.md](pilot-operations.md) § 9 + [pilot-feedback-log.md](pilot-feedback-log.md)
- [x] release notes proces (release-please + pilotné oznámenie) → [pilot-operations.md](pilot-operations.md) § 10

Toto je obsah epicu #15 — po dokončení je produkt „predateľný".

## 7. Riziká

- **Jeden zakladateľ** — podpora + vývoj súčasne; riešenie: cena musí neskôr pokryť aspoň čiastočne outsourcing podpory.
- **Decidim upgrade treadmill** (Rails 7.2 EOL) — držať hostiteľa na 0.31.x, plánovať 0.32 upgrade ako platenú prácu.
- **Obstarávanie VŠ** môže trvať mesiace — pilot podlimitom to obchádza.

---
*Zdroj: stav repozitára v1.2.0, epic #15 (pilot release), #16 (operations). Tento dokument je obchodný plán, nie právne poradenstvo.*
