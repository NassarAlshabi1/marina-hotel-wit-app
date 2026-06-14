const { createCollection } = require('./lib');

async function main() {
  console.log('=== Batch 4: booking_notes + shift_notes + booking_nights ===');

  await createCollection('booking_notes', [
    { key: 'bookingId', type: 'integer', required: true },
    { key: 'noteText', type: 'string', size: 4096, required: true },
    { key: 'alertType', type: 'string', size: 50, required: true },
    { key: 'alertUntil', type: 'string', size: 50, required: false },
    { key: 'isActive', type: 'integer', required: false, default: 1 },
  ]);

  await createCollection('shift_notes', [
    { key: 'title', type: 'string', size: 255, required: true },
    { key: 'content', type: 'string', size: 8192, required: true },
    { key: 'priority', type: 'string', size: 20, required: false, default: 'medium' },
    { key: 'shiftType', type: 'string', size: 20, required: false, default: 'all' },
    { key: 'isRead', type: 'integer', required: false, default: 0 },
    { key: 'expiresAt', type: 'string', size: 50, required: false },
    { key: 'createdBy', type: 'string', size: 50, required: false, default: 'user' },
  ]);

  await createCollection('booking_nights', [
    { key: 'bookingLocalId', type: 'integer', required: false },
    { key: 'hotelDayKey', type: 'string', size: 50, required: true },
    { key: 'nightStart', type: 'string', size: 50, required: true },
    { key: 'nightEnd', type: 'string', size: 50, required: true },
    { key: 'nightlyRate', type: 'double', required: false, default: 0.0 },
    { key: 'sequence', type: 'integer', required: false, default: 0 },
    { key: 'isProcessedByAutoFix', type: 'boolean', required: false, default: false },
    { key: 'baseRate', type: 'double', required: false, default: 0.0 },
    { key: 'adjustment', type: 'double', required: false, default: 0.0 },
    { key: 'finalRate', type: 'double', required: false, default: 0.0 },
    { key: 'appliedAdjustmentUuid', type: 'string', size: 64, required: false },
    { key: 'appliedAdjustmentsJson', type: 'string', size: 8192, required: false },
  ]);

  console.log('\n✅ Batch 4 complete!');
}

main().catch(console.error);
