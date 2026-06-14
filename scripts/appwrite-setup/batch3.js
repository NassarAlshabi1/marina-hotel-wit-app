const { createCollection } = require('./lib');

async function main() {
  console.log('=== Batch 3: payments + debts ===');

  await createCollection('payments', [
    { key: 'serverPaymentId', type: 'integer', required: false },
    { key: 'bookingLocalId', type: 'integer', required: false },
    { key: 'serverBookingId', type: 'integer', required: false },
    { key: 'roomNumber', type: 'string', size: 20, required: false },
    { key: 'amount', type: 'double', required: true },
    { key: 'paymentDate', type: 'string', size: 50, required: true },
    { key: 'notes', type: 'string', size: 4096, required: false },
    { key: 'paymentMethod', type: 'string', size: 50, required: true },
    { key: 'revenueType', type: 'string', size: 50, required: true },
    { key: 'cashTransactionLocalId', type: 'integer', required: false },
    { key: 'cashTransactionServerId', type: 'integer', required: false },
    { key: 'referenceNumber', type: 'string', size: 100, required: false },
    { key: 'hotelDayKey', type: 'string', size: 50, required: false },
    { key: 'isPendingBalance', type: 'boolean', required: false, default: false },
    { key: 'linkedDebtUuid', type: 'string', size: 64, required: false },
    { key: 'bookingUuidCache', type: 'string', size: 64, required: false },
    { key: 'discountAmount', type: 'double', required: false },
    { key: 'discountStartDate', type: 'string', size: 50, required: false },
    { key: 'isVoided', type: 'boolean', required: false, default: false },
    { key: 'voidedAt', type: 'integer', required: false },
    { key: 'voidedBy', type: 'string', size: 128, required: false },
  ]);

  await createCollection('debts', [
    { key: 'bookingLocalId', type: 'integer', required: false },
    { key: 'guestName', type: 'string', size: 255, required: true },
    { key: 'checkinDate', type: 'string', size: 50, required: true },
    { key: 'checkoutDate', type: 'string', size: 50, required: true },
    { key: 'dateRecorded', type: 'string', size: 50, required: false, default: '' },
    { key: 'debtReason', type: 'string', size: 512, required: false, default: '' },
    { key: 'totalAmount', type: 'double', required: true },
    { key: 'paidAmount', type: 'double', required: true },
    { key: 'remainingAmount', type: 'double', required: true },
    { key: 'paymentDate', type: 'string', size: 50, required: true },
    { key: 'isSettled', type: 'integer', required: false, default: 0 },
    { key: 'pledge', type: 'string', size: 512, required: false },
    { key: 'pledgeType', type: 'string', size: 50, required: false },
    { key: 'note', type: 'string', size: 2048, required: false },
    { key: 'debtUuid', type: 'string', size: 64, required: false },
    { key: 'hotelDayOpened', type: 'string', size: 50, required: false },
    { key: 'hotelDayClosed', type: 'string', size: 50, required: false },
    { key: 'isFromAutoFix', type: 'boolean', required: false, default: false },
    { key: 'settlementConfirmed', type: 'boolean', required: false, default: false },
  ]);

  console.log('\n✅ Batch 3 complete!');
}

main().catch(console.error);
