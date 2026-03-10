const https = require('https');

const ENDPOINT = 'fra.cloud.appwrite.io';
const PROJECT_ID = '690ff0da0025518570c1';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';
const DATABASE_ID = 'hotel_db';

function makeRequest(path, queries = []) {
    return new Promise((resolve, reject) => {
        let fullPath = path;
        if (queries.length > 0) {
            fullPath += '?' + queries.map(q => `queries[]=${encodeURIComponent(q)}`).join('&');
        }
        
        const options = {
            hostname: ENDPOINT,
            port: 443,
            path: fullPath,
            method: 'GET',
            headers: {
                'Content-Type': 'application/json',
                'X-Appwrite-Project': PROJECT_ID,
                'X-Appwrite-Key': API_KEY,
            }
        };
        
        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve(JSON.parse(data)));
        });
        
        req.on('error', reject);
        req.end();
    });
}

async function main() {
    console.log('🔍 Checking for deleted/stuck attributes...\n');
    
    for (const collId of ['bookings', 'payments', 'debts']) {
        console.log(`\n📦 ${collId.toUpperCase()}:`);
        
        // Try with queries for different statuses
        const queries = ['equal("status", "deleted")', 'equal("status", "stuck")', 'equal("status", "processing")'];
        
        for (const q of queries) {
            try {
                const result = await makeRequest(`/v1/databases/${DATABASE_ID}/collections/${collId}/attributes`, [q]);
                if (result.attributes && result.attributes.length > 0) {
                    console.log(`   Found with query ${q}:`);
                    result.attributes.forEach(a => console.log(`      - ${a.key} (${a.status})`));
                }
            } catch (e) {
                // Query might not be supported
            }
        }
        
        // Also try without any filter to see total
        const allResult = await makeRequest(`/v1/databases/${DATABASE_ID}/collections/${collId}/attributes`);
        console.log(`   Total reported: ${allResult.total}`);
        console.log(`   Actually returned: ${allResult.attributes.length}`);
        
        // The difference is likely deleted attributes that are still in the system
        if (allResult.total > allResult.attributes.length) {
            const diff = allResult.total - allResult.attributes.length;
            console.log(`   ⚠️  Hidden/deleted attributes: ${diff}`);
            console.log(`      These might be blocking creation of new attributes with same names.`);
        }
    }
}

main().catch(console.error);
