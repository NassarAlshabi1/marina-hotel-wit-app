# Targeted salary UUID and pull-quarantine fixes

Scope: salary carry-over employee identity, salary-payment cycle UUID cache, and
non-silent pull rejection only. Financial calculations and sync lifetime are unchanged.

- `salary_carry_over_logs.employee_uuid` and `salary_payments.cycle_uuid` already
  exist in Room, domain mapping, local creation/outbox payloads and Worker handling.
  Do not add duplicate columns or another competing cycle identity field.
- When an incoming update omits a UUID and an existing local child has an empty
  cache, recover it only from the child's **already stored local parent ID**.
  Never treat the incoming device's numeric ID as a local parent ID. Explicit
  incoming UUID resolution remains authoritative and missing parents stay in
  `pending_sync_links` for retry.
- Missing entity, unsupported entity, missing/blank UUID, and invalid records are
  failed pull records, not successful skips. Store the full payload and reason in
  local-only Room `sync_quarantine`, transactionally with the page. Stable UUID or
  SHA-256 payload keys prevent identical retries from growing duplicate evidence.
- Existing failure reporting prevents the pull cursor from advancing over a
  quarantined page. A corrected record for the same UUID clears its quarantine
  after successful handling. Ordinary LWW skips (local data is newer) remain safe
  skips and are not quarantined. Unknown-UUID evidence remains available for review.
- Schema 73 adds only the quarantine table via migration 72→73; the complete
  70→71→72→73 upgrade path preserves money, outbox and pending links. Quarantine
  has no outbox producer, is not uploaded, and its payload is never logged.

Regression tests cover salary cache recovery despite misleading remote IDs,
malformed/unknown/missing-UUID records, deduplicated quarantine, correction and LWW,
real database close/reopen, unchanged pull cursor, and migration from 70/71/72.
CI verification is required; these tests were not executable locally (no Android/JDK toolchain).
