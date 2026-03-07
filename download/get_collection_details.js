const https = require('https');

const ENDPOINT = 'fra.cloud.appwrite.io';
const PROJECT_ID = '690ff0da0025518570c1';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';
const DATABASE_ID = 'hotel_db';

function makeRequest(path, method = 'GET') {
    return new Promise((resolve, reject) => {
        const options = {
            hostname: ENDPOINT,
            port: 443,
            path: path,
            method: method,
            headers: {
                'Content-Type': 'application/json',
                'X-Appwrite-Project': PROJECT_ID,
                'X-Appwrite-Key': API_KEY,
            }
        };
        
        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, data: JSON.parse(data) });
                } catch (e) {
                    resolve({ status: res.statusCode, data: data });
                }
            });
        });
        
        req.on('error', reject);
        req.end();
    });
}

async function main() {
    console.log('🔍 Getting detailed collection info...\n');
    
    for (const collId of ['bookings', 'payments', 'debts']) {
        console.log(`\n📦 ${collId.toUpperCase()}:`);
        console.log('='.repeat(60));
        
        // Get collection details
        const collResult = await makeRequest(`/v1/databases/${DATABASE_ID}/collections/${collId}`);
        if (collResult.data) {
            console.log(`   Name: ${collResult.data.name}`);
            console.log(`   Document Security: ${collResult.data.documentSecurity}`);
            console.log(`   Enabled: ${collResult.data.enabled}`);
        }
        
        // Get attributes with full details
        const attrsResult = await makeRequest(`/v1/databases/${DATABASE_ID}/collections/${collId}/attributes`);
        if (attrsResult.data?.attributes) {
            const available = attrsResult.data.attributes.filter(a => a.status === 'available');
            const processing = attrsResult.data.attributes.filter(a => a.status === 'processing');
            const deleted = attrsResult.data.attributes.filter(a => a.status === 'deleted');
            const stuck = attrsResult.data.attributes.filter(a => a.status === 'stuck');
            const other = attrsResult.data.attributes.filter(a => !['available', 'processing', 'deleted', 'stuck'].includes(a.status));
            
            console.log(`   Total in response: ${attrsResult.data.total}`);
            console.log(`   Available: ${available.length}`);
            console.log(`   Processing: ${processing.length}`);
            console.log(`   Deleted: ${deleted.length}`);
            console.log(`   Stuck: ${stuck.length}`);
            console.log(`   Other: ${other.length}`);
            
            if (deleted.length > 0) {
                console.log(`\n   Deleted attributes:`);
                deleted.forEach(a => console.log(`      - ${a.key} (${a.type})`));
            }
            
            if (processing.length > 0) {
                console.log(`\n   Processing attributes:`);
                processing.forEach(a => console.log(`      - ${a.key} (${a.type})`));
            }
            
            if (stuck.length > 0) {
                console.log(`\n   Stuck attributes:`);
                stuck.forEach(a => console.log(`      - ${a.key} (${a.type})`));
            }
        }
    }
}

main().catch(console.error);
