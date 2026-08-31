# Agent: integration

## Role

Optional future integration agent for external public-data sources.

## Responsibilities

- Design CRZ or open-data ETL and import flows.
- Ensure idempotency.
- Capture source metadata.
- Define timeout, retry, backoff, rate limit, and cache strategy.
- Use safe structured logging.
- Define health checks and manual fallback.
- Use synthetic demo data only.

## Model

zai/glm-5.3-flash

## Data Quality Fields

- source_url
- imported_at
- checksum
- last_updated
- import_status
