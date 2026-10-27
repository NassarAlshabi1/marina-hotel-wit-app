#!/usr/bin/env node

const { Client, Databases } = require('node-appwrite');

function readStdin() {
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', chunk => (data += chunk));
    process.stdin.on('end', () => resolve(data.trim()));
    process.stdin.on('error', reject);
  });
}

function parseInput(str) {
  if (!str) return [];
  const first = str.trim()[0];
  if (first === '[') {
    try {
      const arr = JSON.parse(str);
      if (Array.isArray(arr)) return arr;
      throw new Error('Top-level JSON is not an array');
    } catch (e) {
      throw new Error('Failed to parse JSON array from stdin: ' + e.message);
    }
  }
  const lines = str.split(/\r?\n/).filter(l => l.trim().length > 0);
  const entries = [];
  for (const line of lines) {
    try {
      entries.push(JSON.parse(line));
    } catch (e) {
      throw new Error('Failed to parse NDJSON line: ' + line.slice(0, 200));
    }
  }
  return entries;
}

function snakeToCamelKey(key) {
  return key.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
}

function normalizePayloadKeys(obj) {
  if (!obj || typeof obj !== 'object') return {};
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    const nk = snakeToCamelKey(k);
    if (v && typeof v === 'object' && !Array.isArray(v)) {
      out[nk] = normalizePayloadKeys(v);
    } else {
      out[nk] = v;
    }
  }
  return out;
}

function nowEpoch() {
  return Math.floor(Date.now());
}

const COLLECTIONS = {
  rooms: 'rooms',
  bookings: 'bookings',
  booking_notes: 'booking_notes',
  booking_nights: 'booking_nights',
  employees: 'employees',
  expenses: 'expenses',
  payments: 'payments',
  debts: 'debts',
  cash_transactions: 'cash_transactions',
  salary_cycles: 'salary_cycles',
  salary_payments: 'salary_payments',
  shift_notes: 'shift_notes',
  hotel_day_ledger: 'hotel_day_ledger',
};

function mapPayload(entity, payload, localUuid, clientTs) {
  const camel = normalizePayloadKeys(payload || {});
  const ts = Number.isFinite(clientTs) ? clientTs : nowEpoch();
  const base = {
    localUuid,
    updatedAt: camel.updatedAt ?? ts,
    createdAt: camel.createdAt ?? ts,
    lastModified: camel.lastModified ?? ts,
    version: camel.version ?? 1,
    origin: camel.origin ?? 'local',
  };

  switch (entity) {
    case 'rooms': {
      // Ensure required fields exist even if payload was minimal
      return {
        roomNumber: camel.roomNumber,
        type: camel.type,
        price: camel.price,
        status: camel.status,
        imageUrl: camel.imageUrl,
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    case 'bookings': {
      return {
        serverBookingId: camel.serverBookingId,
        roomNumber: camel.roomNumber,
        guestName: camel.guestName,
        guestPhone: camel.guestPhone,
        guestIdType: camel.guestIdType,
        guestIdNumber: camel.guestIdNumber,
        guestIdIssueDate: camel.guestIdIssueDate,
        guestIdIssuePlace: camel.guestIdIssuePlace,
        guestNationality: camel.guestNationality,
        guestEmail: camel.guestEmail,
        guestAddress: camel.guestAddress,
        checkinDate: camel.checkinDate,
        checkoutDate: camel.checkoutDate,
        actualCheckout: camel.actualCheckout,
        status: camel.status,
        notes: camel.notes,
        expectedNights: camel.expectedNights,
        calculatedNights: camel.calculatedNights,
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    case 'payments': {
      return {
        serverPaymentId: camel.serverPaymentId,
        bookingLocalId: camel.bookingLocalId,
        serverBookingId: camel.serverBookingId,
        roomNumber: camel.roomNumber,
        amount: camel.amount,
        paymentDate: camel.paymentDate,
        notes: camel.notes,
        paymentMethod: camel.paymentMethod,
        revenueType: camel.revenueType,
        cashTransactionLocalId: camel.cashTransactionLocalId,
        cashTransactionServerId: camel.cashTransactionServerId,
        referenceNumber: camel.referenceNumber,
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    case 'expenses': {
      return {
        expenseType: camel.expenseType,
        relatedId: camel.relatedId,
        description: camel.description,
        amount: camel.amount,
        date: camel.date,
        cashTransactionId: camel.cashTransactionId,
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    case 'debts': {
      return {
        amount: camel.amount,
        debtorName: camel.debtorName || camel.debtor_name, // fallback if not normalized
        dueDate: camel.dueDate,
        status: camel.status,
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    case 'cash_transactions': {
      return {
        registerId: camel.registerId,
        transactionType: camel.transactionType,
        amount: camel.amount,
        referenceType: camel.referenceType,
        referenceId: camel.referenceId,
        description: camel.description,
        transactionTime: camel.transactionTime,
        createdBy: camel.createdBy,
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    case 'shift_notes': {
      return {
        title: camel.title,
        content: camel.content,
        priority: camel.priority ?? 'medium',
        shiftType: camel.shiftType ?? 'all',
        isRead: camel.isRead ?? 0,
        expiresAt: camel.expiresAt,
        createdBy: camel.createdBy ?? 'user',
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    case 'booking_notes': {
      return {
        bookingId: camel.bookingId,
        noteText: camel.noteText,
        noteType: camel.noteType ?? 'general',
        createdBy: camel.createdBy,
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    case 'booking_nights': {
      return {
        bookingLocalId: camel.bookingLocalId,
        hotelDayKey: camel.hotelDayKey,
        nightDate: camel.nightDate,
        nightPrice: camel.nightPrice,
        roomNumber: camel.roomNumber,
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    case 'employees': {
      return {
        name: camel.name,
        role: camel.role,
        phone: camel.phone,
        nationalId: camel.nationalId,
        hireDate: camel.hireDate,
        salary: camel.salary,
        status: camel.status ?? 'active',
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    case 'salary_cycles': {
      return {
        employeeId: camel.employeeId,
        cycleStartDate: camel.cycleStartDate,
        cycleEndDate: camel.cycleEndDate,
        baseSalary: camel.baseSalary,
        deductions: camel.deductions ?? 0,
        bonuses: camel.bonuses ?? 0,
        netSalary: camel.netSalary,
        status: camel.status ?? 'pending',
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    case 'salary_payments': {
      return {
        cycleId: camel.cycleId,
        employeeId: camel.employeeId,
        amount: camel.amount,
        paymentDate: camel.paymentDate,
        paymentMethod: camel.paymentMethod ?? 'cash',
        notes: camel.notes,
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    case 'hotel_day_ledger': {
      return {
        dayKey: camel.dayKey,
        totalRevenue: camel.totalRevenue ?? 0,
        totalExpenses: camel.totalExpenses ?? 0,
        netIncome: camel.netIncome ?? 0,
        occupancyRate: camel.occupancyRate ?? 0,
        serverId: camel.serverId,
        deletedAt: camel.deletedAt,
        ...base,
      };
    }
    default:
      return { ...camel, ...base };
  }
}

async function upsert(databases, databaseId, collectionId, docId, data) {
  try {
    await databases.updateDocument(databaseId, collectionId, docId, data);
    return { ok: true, method: 'update' };
  } catch (e) {
    if (e?.code === 404) {
      try {
        await databases.createDocument(databaseId, collectionId, docId, data);
        return { ok: true, method: 'create' };
      } catch (e2) {
        return { ok: false, error: e2 };
      }
    }
    return { ok: false, error: e };
  }
}

async function main() {
  const endpoint = process.env.APPWRITE_ENDPOINT;
  const projectId = process.env.APPWRITE_PROJECT;
  const apiKey = process.env.APPWRITE_API_KEY;
  const databaseId = process.env.APPWRITE_DATABASE_ID || 'hotel_db';

  if (!endpoint || !projectId || !apiKey) {
    console.error('Missing APPWRITE_ENDPOINT, APPWRITE_PROJECT, APPWRITE_API_KEY');
    process.exit(1);
  }

  const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
  const databases = new Databases(client);

  const stdin = await readStdin();
  const items = parseInput(stdin);
  if (!items.length) {
    console.log(JSON.stringify({ processed: 0, successes: 0, failures: [] }));
    return;
  }

  const failures = [];
  let successes = 0;

  for (const [idx, item] of items.entries()) {
    const entity = String(item.entity || '').trim();
    const op = String(item.op || '').trim().toLowerCase();
    const localUuid = String(item.localUuid || item.local_uuid || '').trim();
    const clientTs = Number(item.clientTs || item.client_ts || Date.now());
    const payload = item.payload || {};

    if (!entity || !COLLECTIONS[entity]) {
      failures.push({ index: idx, error: `Unknown or missing entity: ${entity}` });
      continue;
    }
    if (!localUuid) {
      failures.push({ index: idx, error: 'Missing localUuid' });
      continue;
    }

    const collectionId = COLLECTIONS[entity];

    try {
      if (op === 'delete') {
        try {
          await databases.deleteDocument(databaseId, collectionId, localUuid);
          successes++;
        } catch (e) {
          if (e?.code === 404) {
            successes++; // already deleted
          } else {
            failures.push({ index: idx, entity, op, localUuid, error: e.message || String(e) });
          }
        }
        continue;
      }

      const data = mapPayload(entity, payload, localUuid, clientTs);
      const result = await upsert(databases, databaseId, collectionId, localUuid, data);
      if (result.ok) {
        successes++;
      } else {
        failures.push({ index: idx, entity, op, localUuid, error: result.error?.message || String(result.error) });
      }
    } catch (e) {
      failures.push({ index: idx, entity, op, localUuid, error: e.message || String(e) });
    }
  }

  console.log(JSON.stringify({ processed: items.length, successes, failures }, null, 2));
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
