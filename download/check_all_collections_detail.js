const { Client, Databases } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';
const DATABASE_ID = 'hotel_db';

const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new Databases(client);

async function main() {
    console.log('\n╔══════════════════════════════════════════════════════════════════════════════╗');
    console.log('║  🔍 فحص تفصيلي لجميع Collections                                               ║');
    console.log('╚══════════════════════════════════════════════════════════════════════════════╝\n');
    
    try {
        // List all collections
        const collections = await databases.listCollections(DATABASE_ID);
        
        for (const collection of collections.collections) {
            console.log(`\n📦 Collection: ${collection.name} (${collection.$id})`);
            console.log('─'.repeat(80));
            
            const attrs = await databases.listAttributes(DATABASE_ID, collection.$id);
            
            // Group by required
            const required = attrs.attributes.filter(a => a.required === true);
            const optional = attrs.attributes.filter(a => a.required !== true);
            
            console.log(`\n✅ الحقول المطلوبة (${required.length}):`);
            required.forEach(a => {
                const type = a.type || 'string';
                const size = a.size ? ` [${a.size}]` : '';
                console.log(`   • ${a.key} (${type})${size}`);
            });
            
            // Check for snake_case in required
            const snakeCaseRequired = required.filter(a => a.key.includes('_'));
            if (snakeCaseRequired.length > 0) {
                console.log(`\n⚠️  تنبيه: حقول snake_case مطلوبة!`);
                snakeCaseRequired.forEach(a => {
                    console.log(`   ❗ ${a.key} - يجب تحويله إلى camelCase`);
                });
            }
            
            console.log(`\n📝 الحقول الاختيارية (${optional.length}):`);
            if (optional.length <= 10) {
                optional.forEach(a => console.log(`   ○ ${a.key}`));
            } else {
                optional.slice(0, 8).forEach(a => console.log(`   ○ ${a.key}`));
                console.log(`   ... و ${optional.length - 8} أخرى`);
            }
        }
        
    } catch (error) {
        console.log('❌ خطأ:', error.message);
    }
    
    console.log('\n' + '═'.repeat(80) + '\n');
}

main().catch(console.error);
