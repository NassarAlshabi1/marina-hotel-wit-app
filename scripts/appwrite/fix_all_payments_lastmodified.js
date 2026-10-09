const { Client, Databases, Query } = require('node-appwrite');
const client = new Client().setEndpoint('https://fra.cloud.appwrite.io/v1').setProject('6a2b01d0000752ce97e7').setKey(process.env.APPWRITE_API_KEY);
const databases = new Databases(client);
const DB = '6a2b030d000445596163';

(async () => {
  const now = Math.floor(Date.now() / 1000);
  let updated = 0;
  let total = 0;
  let cursor = null;

  while (true) {
    const queries = [Query.limit(100)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const r = await databases.listDocuments(DB, 'payments', queries);
    if (r.documents.length === 0) break;
    total += r.documents.length;

    const batch = r.documents;
    for (let i = 0; i < batch.length; i += 5) {
      const chunk = batch.slice(i, i + 5);
      await Promise.all(chunk.map(async (p) => {
        try {
          await databases.updateDocument(DB, 'payments', p.$id, { lastModified: now });
          updated++;
        } catch (e) {}
      }));
    }

    process.stdout.write('.');
    if (r.documents.length < 100) break;
    cursor = r.documents[r.documents.length - 1].$id;
  }

  console.log('\nDone: ' + updated + '/' + total + ' payments updated to lastModified=' + now);
})().catch(e => console.error('Error:', e.message));
