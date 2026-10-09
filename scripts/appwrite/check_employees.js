#!/usr/bin/env node

const { Client, Databases } = require('node-appwrite');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey('standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da');

const databases = new Databases(client);

async function checkEmployees() {
    try {
        console.log('🔍 Checking Employees Collection...\n');
        
        // Get collection info
        const collection = await databases.getCollection('hotel_db', 'employees');
        console.log(`📁 Collection: ${collection.name} (${collection.$id})`);
        console.log(`   Created: ${collection.$createdAt}`);
        console.log(`   Attributes: ${collection.attributes.length}\n`);
        
        // List attributes
        console.log('📋 Attributes:');
        collection.attributes.forEach(attr => {
            const details = [];
            details.push(`type: ${attr.type}`);
            if (attr.size) details.push(`size: ${attr.size}`);
            if (attr.required) details.push('required');
            if (attr.array) details.push('array');
            
            console.log(`   • ${attr.key} (${details.join(', ')})`);
        });
        
        // List documents
        console.log('\n📄 Documents:');
        const docs = await databases.listDocuments('hotel_db', 'employees');
        console.log(`   Total: ${docs.total}`);
        
        if (docs.total > 0) {
            console.log('\n   Employees:');
            docs.documents.forEach((doc, i) => {
                console.log(`   ${i + 1}. ${doc.name || 'N/A'}`);
                console.log(`      Position: ${doc.position || 'N/A'}`);
                console.log(`      Salary: ${doc.basicSalary || 0}`);
                console.log(`      Status: ${doc.status || 'N/A'}`);
                console.log(`      Phone: ${doc.phone || 'N/A'}`);
            });
        } else {
            console.log('   ⚪ No employees found in Appwrite');
            console.log('   💡 Use the app to add employees, or they will sync from mobile');
        }
        
        // List indexes
        const indexes = await databases.listIndexes('hotel_db', 'employees');
        console.log(`\n🔗 Indexes: ${indexes.total}`);
        if (indexes.total > 0) {
            indexes.indexes.forEach(idx => {
                console.log(`   • ${idx.key} (${idx.type}) → [${idx.attributes.join(', ')}]`);
            });
        }
        
    } catch (error) {
        console.error('❌ Error:', error.message);
    }
}

checkEmployees();
