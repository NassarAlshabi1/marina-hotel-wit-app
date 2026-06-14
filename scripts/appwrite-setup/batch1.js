const { createCollection } = require('./lib');

async function main() {
  console.log('=== Batch 1: rooms + bookings ===');
  
  await createCollection('rooms', [
    { key: 'roomNumber', type: 'string', size: 20, required: true },
    { key: 'type', type: 'string', size: 100, required: true },
    { key: 'price', type: 'double', required: true },
    { key: 'status', type: 'string', size: 50, required: true },
    { key: 'imageUrl', type: 'string', size: 2048, required: false },
    { key: 'cleaningStatus', type: 'string', size: 50, required: false, default: 'clean' },
    { key: 'lastCleanedHotelDay', type: 'string', size: 50, required: false },
    { key: 'lastOccupiedHotelDay', type: 'string', size: 50, required: false },
    { key: 'requiresMaintenance', type: 'boolean', required: false, default: false },
  ]);

  await createCollection('bookings', [
    { key: 'serverBookingId', type: 'integer', required: false },
    { key: 'roomNumber', type: 'string', size: 20, required: true },
    { key: 'guestName', type: 'string', size: 255, required: true },
    { key: 'guestPhone', type: 'string', size: 50, required: true },
    { key: 'guestIdType', type: 'string', size: 100, required: false, default: '\u0628\u0637\u0627\u0642\u0629 \u0634\u062e\u0635\u064a\u0629' },
    { key: 'guestIdNumber', type: 'string', size: 100, required: false, default: '' },
    { key: 'guestIdIssueDate', type: 'string', size: 50, required: false },
    { key: 'guestIdIssuePlace', type: 'string', size: 255, required: false },
    { key: 'guestNationality', type: 'string', size: 100, required: true },
    { key: 'guestEmail', type: 'string', size: 255, required: false },
    { key: 'guestAddress', type: 'string', size: 512, required: false },
    { key: 'checkinDate', type: 'string', size: 50, required: true },
    { key: 'checkoutDate', type: 'string', size: 50, required: false },
    { key: 'actualCheckout', type: 'string', size: 50, required: false },
    { key: 'status', type: 'string', size: 50, required: true },
    { key: 'notes', type: 'string', size: 4096, required: false },
    { key: 'discount', type: 'double', required: false, default: 0 },
    { key: 'discountType', type: 'string', size: 50, required: false, default: 'per_night' },
    { key: 'discountStartDate', type: 'string', size: 50, required: false },
    { key: 'expectedNights', type: 'integer', required: false, default: 1 },
    { key: 'calculatedNights', type: 'integer', required: false, default: 1 },
    { key: 'totalNightsCached', type: 'integer', required: false, default: 0 },
    { key: 'stayDurationIso', type: 'string', size: 50, required: false },
    { key: 'lastNightEpoch', type: 'integer', required: false },
    { key: 'isOverdue', type: 'boolean', required: false, default: false },
    { key: 'needsCheckoutReview', type: 'boolean', required: false, default: false },
    { key: 'totalDueCached', type: 'double', required: false, default: 0.0 },
    { key: 'totalPaidCached', type: 'double', required: false, default: 0.0 },
    { key: 'remainingBalanceCached', type: 'double', required: false, default: 0.0 },
    { key: 'isFullyPaid', type: 'boolean', required: false, default: false },
    { key: 'hotelDayCheckin', type: 'string', size: 50, required: false },
    { key: 'hotelDayCheckout', type: 'string', size: 50, required: false },
  ]);

  console.log('\n✅ Batch 1 complete!');
}

main().catch(console.error);
