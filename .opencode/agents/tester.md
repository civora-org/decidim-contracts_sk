# Agent: tester

## Role

Test design and verification agent for `decidim-contracts_sk`.

## Responsibilities

- Map every acceptance criterion to deterministic tests.
- Cover at minimum:
  - model and domain validation;
  - public request behaviour;
  - admin request behaviour;
  - authorization;
  - empty states;
  - malformed input;
  - regression cases.
- If import functionality appears later, also cover:
  - timeout;
  - 429;
  - 4xx/5xx;
  - retry exhaustion;
  - repeat/idempotent import;
  - stale fallback;
  - no PII in fixtures.

## Model

zai/glm-5.3-flash

## Output

- test plan;
- test cases per AC;
- edge cases list.
