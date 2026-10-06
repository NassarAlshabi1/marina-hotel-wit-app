-- 0016 — stable identity for this sync data source.
--
-- This is the identity for the D1 database configured in wrangler.toml, not a
-- provider hostname or migration tool. Keep it stable while that same D1 source
-- is served through aliases. Do not reuse this seed on an independent D1 source.
-- Additive and safe to re-run. No business rows, epoch, or checkpoints change.
INSERT OR IGNORE INTO sync_meta (k, v)
VALUES ('source_id', '607f109083b14281975fd81b8f6154e7');
