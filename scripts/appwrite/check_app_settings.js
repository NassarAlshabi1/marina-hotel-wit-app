const { Client, Databases } = require('node-appwrite');
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';
async function main() {
  const client = new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
  const databases = new Databases(client);
  const { attributes } = await databases.listAttributes(DATABASE_ID, 'app_settings');
  const attrs = attributes.filter(a => a.key && !a.key.startsWith('$')).sort((a,b) => a.key.localeCompare(b.key));
  console.log(`Total: ${attrs.length} attributes\n`);
  for (const a of attrs) {
    const req = a.required ? 'REQ' : 'OPT';
    const sz = a.size ? `(${a.size})` : '';
    const def = a.default !== null && a.default !== undefined ? ` def=${JSON.stringify(a.default)}` : '';
    const st = a.status !== 'available' ? ` [${a.status}]` : '';
    console.log(`  ${a.key}: ${a.type}${sz} ${req}${def}${st}`);
  }
}
main().catch(e => { console.error(e); process.exit(1); });
