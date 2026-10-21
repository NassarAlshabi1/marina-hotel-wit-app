-- Add the guest entry date used by the mobile information PDF.
-- Nullable by design: legacy guest records must remain without a date.
ALTER TABLE guest_infos ADD COLUMN entry_date TEXT;
