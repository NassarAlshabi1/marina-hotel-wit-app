const { Client, Databases, Query } = require("node-appwrite");

const endpoint = "https://fra.cloud.appwrite.io/v1";
const project = "6a2b01d0000752ce97e7";
const apiKey = "standard_721adc4e95401dab9274bc2a7596ce0a61bfcdf7bbe37e7c64d52fb2113414e27c8d3e8f1977ebaafcf8ae63e7f3c873aad38c2a07e3ab93229cd7cd745a3ad2f6b9ec3fc407e8abfae2be3e5be00315f4d4a74cc07bc5ba5b0eda13e4569c8ee8ce2532a7bd43d827c7b83a84495974b9995d12f031e2bead685cebbe31aa3d";
const database = "6a2b030d000445596163";

const client = new Client().setEndpoint(endpoint).setProject(project).setKey(apiKey);
const db = new Databases(client);

async function listAll(col) {
  const keys = new Set();
  let offset = 0;
  while (true) {
    try {
      const res = await db.listAttributes(database, col, [
        Query.limit(100),
        Query.offset(offset),
      ]);
      const attrs = res.attributes.map(a => a.key);
      attrs.forEach(k => keys.add(k));
      console.log(`  fetched ${attrs.length} (offset=${offset})`);
      if (attrs.length < 100) break;
      offset += attrs.length;
    } catch (e) {
      console.log(`  error at offset ${offset}: ${e.message || e}`);
      break;
    }
  }
  return keys;
}

(async () => {
  const cols = ["rooms","bookings","payments","expenses","employees","debts","booking_notes","booking_nights","cash_transactions","shift_notes","salary_cycles","salary_payments","salary_withdrawals","salary_carry_over_logs","price_adjustments","booking_price_adjustments","audit_logs","payment_voids","guest_infos","blacklist","devices","sync_logs","app_settings","sync_state","app_users"];
  for (const col of cols) {
    console.log(`=== ${col} ===`);
    const keys = await listAll(col);
    console.log(`Total ${col}: ${keys.size}`);
    console.log(JSON.stringify([...keys].sort()));
  }
})();
