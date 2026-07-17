const { Client, Account, Databases } = require('node-appwrite');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey('4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da');

const databases = new Databases(client);

async function testConnection() {
    try {
        console.log('Testing connection...');
        // Try to list databases
        const dbs = await databases.list();
        console.log('✅ Connection successful!');
        console.log('Databases found:', dbs.total);
        dbs.databases.forEach(db => console.log(` - ${db.name} (${db.$id})`));
    } catch (e) {
        console.error('❌ Connection failed:');
        console.error(e);
    }
}

testConnection();
