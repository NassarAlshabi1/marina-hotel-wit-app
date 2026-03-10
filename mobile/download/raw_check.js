const https = require('https');

const ENDPOINT = 'fra.cloud.appwrite.io';
const PROJECT_ID = '690ff0da0025518570c1';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';
const DATABASE_ID = 'hotel_db';

function makeRequest(path) {
    return new Promise((resolve, reject) => {
        const options = {
            hostname: ENDPOINT,
            port: 443,
            path: path,
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
            res.on('end', () => resolve(data));
        });
        
        req.on('error', reject);
        req.end();
    });
}

async function main() {
    console.log('🔍 RAW API Response for bookings attributes:\n');
    
    const rawData = await makeRequest(`/v1/databases/${DATABASE_ID}/collections/bookings/attributes`);
    const parsed = JSON.parse(rawData);
    
    console.log(`Total: ${parsed.total}`);
    console.log(`Attributes array length: ${parsed.attributes.length}`);
    console.log('\nAll statuses:');
    
    const statusCount = {};
    parsed.attributes.forEach(a => {
        const s = a.status || 'undefined';
        statusCount[s] = (statusCount[s] || 0) + 1;
    });
    
    Object.entries(statusCount).forEach(([s, c]) => console.log(`  ${s}: ${c}`));
    
    // Show all attributes with their status
    console.log('\nAll attributes:');
    parsed.attributes.forEach((a, i) => {
        console.log(`${String(i+1).padStart(2)}. ${a.key.padEnd(25)} status="${a.status || 'null'}" type="${a.type}"`);
    });
}

main().catch(console.error);
