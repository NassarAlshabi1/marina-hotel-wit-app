const https = require('https');

const ENDPOINT = 'fra.cloud.appwrite.io';
const PROJECT_ID = '690ff0da0025518570c1';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';
const DATABASE_ID = 'hotel_db';

function makeRequest(path, method, data) {
    return new Promise((resolve, reject) => {
        const body = data ? JSON.stringify(data) : '';
        
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
        
        if (body) {
            options.headers['Content-Length'] = Buffer.byteLength(body);
        }
        
        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    const json = JSON.parse(data);
                    resolve({ status: res.statusCode, data: json });
                } catch (e) {
                    resolve({ status: res.statusCode, data: data });
                }
            });
        });
        
        req.on('error', reject);
        if (body) req.write(body);
        req.end();
    });
}

async function createAttribute(collectionId, attrKey, attrType, required, size = 255) {
    const path = `/v1/databases/${DATABASE_ID}/collections/${collectionId}/attributes/${attrType}`;
    const data = attrType === 'string' 
        ? { key: attrKey, size: size, required: required }
        : { key: attrKey, required: required };
    
    try {
        const result = await makeRequest(path, 'POST', data);
        return result;
    } catch (e) {
        return { error: e.message };
    }
}

async function main() {
    console.log('🔧 Creating missing attributes via REST API\n');
    
    const fieldsToCreate = {
        'bookings': [
            ['createdAt', 'integer', true],
            ['updatedAt', 'integer', true],
            ['deletedAt', 'integer', false],
            ['lastModified', 'integer', true],
            ['version', 'integer', true],
            ['origin', 'string', true, 50],
            ['vectorClock', 'string', true, 2000],
        ],
        'payments': [
            ['version', 'integer', true],
            ['vectorClock', 'string', true, 2000],
        ],
        'debts': [
            ['version', 'integer', true],
            ['origin', 'string', true, 50],
            ['vectorClock', 'string', true, 2000],
        ]
    };
    
    for (const [collectionId, fields] of Object.entries(fieldsToCreate)) {
        console.log(`\n📦 ${collectionId}:`);
        
        for (const [key, type, required, size] of fields) {
            const result = await createAttribute(collectionId, key, type, required, size);
            
            if (result.status === 202 || result.status === 201) {
                console.log(`   ✅ ${key} - Creating...`);
            } else if (result.data?.message?.includes('already exists')) {
                console.log(`   ⏭️  ${key} - Already exists`);
            } else if (result.data?.code === 409) {
                console.log(`   ⏭️  ${key} - Conflict (already exists)`);
            } else {
                console.log(`   ❌ ${key} - ${JSON.stringify(result.data)}`);
            }
            
            await new Promise(r => setTimeout(r, 500));
        }
    }
    
    console.log('\n✅ Done!');
}

main().catch(console.error);
