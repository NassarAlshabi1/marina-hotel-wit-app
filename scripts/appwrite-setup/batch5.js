const { createCollection } = require('./lib');

async function main() {
  console.log('=== Batch 5: price_adjustments + booking_price_adjustments + audit_logs ===');

  await createCollection('price_adjustments', [
    { key: 'targetType', type: 'string', size: 50, required: true },
    { key: 'targetUuid', type: 'string', size: 64, required: true },
    { key: 'adjustmentType', type: 'string', size: 50, required: true },
    { key: 'previousValue', type: 'integer', required: true },
    { key: 'newValue', type: 'integer', required: true },
    { key: 'reason', type: 'string', size: 1024, required: false },
    { key: 'effectiveDate', type: 'string', size: 50, required: true },
    { key: 'appliedBy', type: 'string', size: 128, required: true },
    { key: 'hotelDayKey', type: 'string', size: 50, required: true },
    { key: 'isReversed', type: 'boolean', required: false, default: false },
    { key: 'reversedAt', type: 'string', size: 50, required: false },
    { key: 'reversedBy', type: 'string', size: 128, required: false },
  ]);

  await createCollection('booking_price_adjustments', [
    { key: 'bookingLocalUuid', type: 'string', size: 64, required: true },
    { key: 'bookingLocalId', type: 'integer', required: false },
    { key: 'roomNumber', type: 'string', size: 20, required: false },
    { key: 'adjustmentType', type: 'integer', required: false, default: 0 },
    { key: 'adjustmentMode', type: 'string', size: 50, required: false, default: 'per_night' },
    { key: 'amount', type: 'double', required: false, default: 0.0 },
    { key: 'effectiveHotelDay', type: 'string', size: 50, required: true },
    { key: 'endHotelDay', type: 'string', size: 50, required: false },
    { key: 'isActive', type: 'boolean', required: false, default: true },
    { key: 'reason', type: 'string', size: 1024, required: false },
    { key: 'appliedBy', type: 'string', size: 128, required: false },
    { key: 'cancelledAt', type: 'string', size: 50, required: false },
    { key: 'cancelledBy', type: 'string', size: 128, required: false },
  ]);

  // audit_logs لا يستخدم SyncFields!
  await createCollection('audit_logs', [
    { key: 'localUuid', type: 'string', size: 64, required: true },
    { key: 'operationType', type: 'string', size: 50, required: true },
    { key: 'entityType', type: 'string', size: 50, required: true },
    { key: 'entityUuid', type: 'string', size: 64, required: true },
    { key: 'entityId', type: 'integer', required: false },
    { key: 'previousState', type: 'string', size: 16384, required: false },
    { key: 'newState', type: 'string', size: 16384, required: false },
    { key: 'changedFields', type: 'string', size: 4096, required: false },
    { key: 'performedBy', type: 'string', size: 128, required: true },
    { key: 'deviceId', type: 'string', size: 128, required: true },
    { key: 'ipAddress', type: 'string', size: 50, required: false },
    { key: 'hotelDayKey', type: 'string', size: 50, required: true },
    { key: 'timestamp', type: 'integer', required: true },
    { key: 'timestampIso', type: 'string', size: 50, required: true },
    { key: 'isFinancial', type: 'boolean', required: false, default: false },
    { key: 'amountImpact', type: 'integer', required: false },
    { key: 'createdAt', type: 'integer', required: true },
  ], false); // لا SyncFields لـ audit_logs

  console.log('\n✅ Batch 5 complete!');
}

main().catch(console.error);
