const fs = require('fs');
const path = require('path');

const backupPath = process.argv[2] || '/home/daytona/project/mobile/scripts/appwrite_full_backup_20260619_224853.json';
const outputDir = process.argv[3] || '/home/daytona/project/scripts/appwrite/backup_splits';

if (!fs.existsSync(backupPath)) {
  console.error('Backup file not found:', backupPath);
  process.exit(1);
}

fs.mkdirSync(outputDir, { recursive: true });

const data = JSON.parse(fs.readFileSync(backupPath, 'utf8'));
const collections = data.collections || {};

let totalRecords = 0;
for (const [name, records] of Object.entries(collections)) {
  if (!Array.isArray(records)) continue;
  const outPath = path.join(outputDir, `${name}.json`);
  const payload = {
    metadata: data.metadata,
    collection: name,
    records: records,
  };
  fs.writeFileSync(outPath, JSON.stringify(payload, null, 2));
  totalRecords += records.length;
  console.log(`✔ ${name}: ${records.length} records -> ${outPath}`);
}

console.log(`\nDone. Wrote ${totalRecords} records across ${Object.keys(collections).length} collections to ${outputDir}`);
