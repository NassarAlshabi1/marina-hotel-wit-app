const { Client, Databases, Permission, Role, Query } = require('node-appwrite');

const endpoint = process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const projectId = process.env.APPWRITE_PROJECT || '690ff0da0025518570c1';
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || 'hotel_db';

const args = process.argv.slice(2);
const migrateOnly = args.includes('--migrate-only');
const verifyOnly = args.includes('--verify');
const dryRun = args.includes('--dry-run');

if (!apiKey) {
    console.error('❌ المتغير APPWRITE_API_KEY مطلوب');
    console.log('');
    console.log('📌 الاستخدام:');
    console.log('   APPWRITE_API_KEY=xxx node setup_blacklist_sync.js');
    console.log('   APPWRITE_API_KEY=xxx node setup_blacklist_sync.js --migrate-only');
    console.log('   APPWRITE_API_KEY=xxx node setup_blacklist_sync.js --verify');
    console.log('   APPWRITE_API_KEY=xxx node setup_blacklist_sync.js --dry-run');
    process.exit(1);
}

const client = new Client()
    .setEndpoint(endpoint)
    .setProject(projectId)
    .setKey(apiKey);

const db = new Databases(client);

const delay = (ms) => new Promise(r => setTimeout(r, ms));

const perms = [
    Permission.read(Role.any()),
    Permission.create(Role.any()),
    Permission.update(Role.any()),
    Permission.delete(Role.any()),
];

const BLACKLIST_ATTRIBUTES = [
    { key: 'localUuid',     type: 'string',  size: 36,   required: true  },
    { key: 'name',          type: 'string',  size: 200,  required: true  },
    { key: 'nationality',   type: 'string',  size: 100,  required: false },
    { key: 'nationalId',    type: 'string',  size: 100,  required: false },
    { key: 'phone',         type: 'string',  size: 30,   required: false },
    { key: 'reason',        type: 'string',  size: 500,  required: false },
    { key: 'notes',         type: 'string',  size: 1000, required: false },
    { key: 'reportedBy',    type: 'string',  size: 50,   required: false },
    { key: 'active',        type: 'boolean', required: false },
    { key: 'serverId',      type: 'integer', required: false },
    { key: 'createdAt',     type: 'string',  size: 50,   required: true  },
    { key: 'updatedAt',     type: 'string',  size: 50,   required: false },
    { key: 'deletedAt',     type: 'string',  size: 50,   required: false },
    { key: 'lastModified',  type: 'integer', required: true  },
    { key: 'createdAtIso',  type: 'string',  size: 30,   required: false },
    { key: 'updatedAtIso',  type: 'string',  size: 30,   required: false },
    { key: 'deletedAtIso',  type: 'string',  size: 30,   required: false },
    { key: 'origin',        type: 'string',  size: 20,   required: false },
    { key: 'deviceId',      type: 'string',  size: 100,  required: false },
    { key: 'syncTimestamp', type: 'integer', required: false },
];

const BLACKLIST_INDEXES = [
    { key: 'idx_bl_uuid',   type: 'unique', attributes: ['localUuid']  },
    { key: 'idx_bl_name',   type: 'key',    attributes: ['name']       },
    { key: 'idx_bl_nid',    type: 'key',    attributes: ['nationalId'] },
    { key: 'idx_bl_phone',  type: 'key',    attributes: ['phone']      },
    { key: 'idx_bl_active', type: 'key',    attributes: ['active']     },
];

async function createBlacklistCollection() {
    console.log('\n═══════════════════════════════════════════════');
    console.log('  📂 إنشاء مجموعة القائمة السوداء (blacklist)');
    console.log('═══════════════════════════════════════════════\n');

    const colId = 'blacklist';

    try {
        await db.getCollection(databaseId, colId);
        console.log('   🔸 المجموعة موجودة مسبقاً — سيتم التحقق من الحقول');
    } catch (e) {
        if (e.code === 404) {
            await db.createCollection(databaseId, colId, 'Blacklist', perms);
            console.log('   ✅ تم إنشاء مجموعة: blacklist');
        } else {
            throw e;
        }
    }

    for (const attr of BLACKLIST_ATTRIBUTES) {
        try {
            if (attr.type === 'string') {
                await db.createStringAttribute(databaseId, colId, attr.key, attr.size, attr.required);
            } else if (attr.type === 'integer') {
                await db.createIntegerAttribute(databaseId, colId, attr.key, attr.required);
            } else if (attr.type === 'boolean') {
                await db.createBooleanAttribute(databaseId, colId, attr.key, attr.required);
            }
            console.log(`   ➕ حقل: ${attr.key} (${attr.type}${attr.size ? ' ${attr.size}' : ''})`);
            await delay(150);
        } catch (e) {
            if (e.code === 409) {
                console.log(`   🔸 حقل موجود: ${attr.key}`);
            } else {
                console.error(`   ❌ فشل إنشاء ${attr.key}: ${e.message}`);
            }
        }
    }

    console.log('\n   ⏳ انتظار تجهيز الفهارس...');
    await delay(3000);

    for (const idx of BLACKLIST_INDEXES) {
        try {
            await db.createIndex(databaseId, colId, idx.key, idx.type, idx.attributes);
            console.log(`   📇 فهرس: ${idx.key} [${idx.attributes.join(', ')}]`);
            await delay(150);
        } catch (e) {
            if (e.code === 409) {
                console.log(`   🔸 فهرس موجود: ${idx.key}`);
            } else {
                console.error(`   ❌ فشل إنشاء الفهرس ${idx.key}: ${e.message}`);
            }
        }
    }

    console.log('\n   ✨ اكتمل إنشاء مجموعة القائمة السوداء\n');
}

async function migrateFromShiftNotes() {
    console.log('═══════════════════════════════════════════════');
    console.log('  🔄 نقل بيانات القائمة السوداء من shift_notes');
    console.log('═══════════════════════════════════════════════\n');

    let allDocs = [];
    let offset = 0;
    const limit = 100;

    console.log('   📥 جلب سجلات القائمة السوداء من shift_notes...');

    while (true) {
        const response = await db.listDocuments(
            databaseId, 'shift_notes',
            [Query.equal('createdBy', 'blacklist'), Query.limit(limit), Query.offset(offset)]
        );
        if (response.documents.length === 0) break;
        allDocs = allDocs.concat(response.documents);
        offset += limit;
        if (response.documents.length < limit) break;
        await delay(300);
    }

    console.log(`   📊 تم جلب ${allDocs.length} سجل\n`);

    if (allDocs.length === 0) {
        console.log('   ℹ️ لا توجد بيانات للنقل');
        return;
    }

    let migrated = 0, skipped = 0, errors = 0;

    for (const doc of allDocs) {
        try {
            let payload = {};
            try { payload = JSON.parse(doc.content || '{}'); } catch (_) {}

            const name = doc.title || '';
            if (!name.trim()) {
                console.log(`   ⚠️ تخطي سجل بدون اسم (ID: ${doc.$id})`);
                skipped++;
                continue;
            }

            const blacklistDoc = {
                documentId: doc.$id,
                localUuid: doc.$id,
                name: name,
                nationality: payload.nationality || '',
                nationalId: payload.nationalId || '',
                phone: payload.phone || '',
                reason: payload.reason || '',
                notes: payload.notes || '',
                reportedBy: payload.reportedBy || 'police',
                active: payload.active !== undefined ? payload.active : true,
                createdAt: doc.createdAt || new Date().toISOString(),
                updatedAt: doc.updatedAt || null,
                deletedAt: doc.deletedAt || null,
                lastModified: parseInt(doc.lastModified) || Math.floor(Date.now() / 1000),
                createdAtIso: doc.createdAtIso || null,
                updatedAtIso: doc.updatedAtIso || null,
                deletedAtIso: doc.deletedAtIso || null,
                origin: 'migrated',
                deviceId: doc.deviceId || '',
                syncTimestamp: parseInt(doc.syncTimestamp) || 0,
            };

            if (dryRun) {
                console.log(`   🔍 [DRY-RUN] سيتم نقل: ${name} (${doc.$id})`);
                migrated++;
            } else {
                try {
                    await db.createDocument(databaseId, 'blacklist', doc.$id, blacklistDoc, perms);
                    console.log(`   ✅ نقل: ${name}`);
                    migrated++;
                } catch (e) {
                    if (e.code === 409) {
                        await db.updateDocument(databaseId, 'blacklist', doc.$id, blacklistDoc, perms);
                        console.log(`   🔄 تحديث: ${name}`);
                        migrated++;
                    } else {
                        throw e;
                    }
                }
            }
            await delay(100);
        } catch (e) {
            console.error(`   ❌ فشل نقل ${doc.$id}: ${e.message}`);
            errors++;
        }
    }

    console.log('\n   ────────────────────────────────');
    console.log(`   📊 ملخص النقل: تم ${migrated} | تخطي ${skipped} | أخطاء ${errors}`);
    console.log('   ────────────────────────────────\n');
}

async function verifyCollection() {
    console.log('\n═══════════════════════════════════════════════');
    console.log('  🔍 التحقق من مجموعة القائمة السوداء');
    console.log('═══════════════════════════════════════════════\n');

    try {
        await db.getCollection(databaseId, 'blacklist');
        console.log('   ✅ المجموعة موجودة: blacklist');

        const docs = await db.listDocuments(databaseId, 'blacklist', [Query.limit(1)]);
        console.log(`   📊 عدد السجلات: ${docs.total}`);

        const snDocs = await db.listDocuments(databaseId, 'shift_notes',
            [Query.equal('createdBy', 'blacklist'), Query.limit(1)]);
        console.log(`   📊 سجلات shift_notes (blacklist): ${snDocs.total}`);

        if (docs.total >= snDocs.total) {
            console.log('   ✅ جميع البيانات تم نقلها بنجاح');
        } else {
            console.log(`   ⚠️ يوجد ${snDocs.total - docs.total} سجل لم يتم نقلها`);
        }
    } catch (e) {
        if (e.code === 404) {
            console.log('   ❌ المجموعة غير موجودة — شغّل السكربت بدون --verify');
        } else {
            console.error(`   ❌ خطأ: ${e.message}`);
        }
    }
}

async function addShiftNotesBlacklistIndex() {
    console.log('\n═══════════════════════════════════════════════');
    console.log('  📇 إنشاء فهرس createdBy على shift_notes');
    console.log('═══════════════════════════════════════════════\n');

    try {
        await db.createIndex(databaseId, 'shift_notes', 'idx_sn_createdBy', 'key', ['createdBy']);
        console.log('   ✅ تم إنشاء فهرس idx_sn_createdBy');
    } catch (e) {
        if (e.code === 409) {
            console.log('   🔸 الفهرس موجود مسبقاً');
        } else {
            console.error(`   ⚠️ فشل: ${e.message}`);
        }
    }
}

async function main() {
    console.log('');
    console.log('╔══════════════════════════════════════════════════════╗');
    console.log('║   سكربت إعداد القائمة السوداء — Appwrite Console    ║');
    console.log('╚══════════════════════════════════════════════════════╝');
    console.log(`\n   Endpoint: ${endpoint}`);
    console.log(`   Project:  ${projectId}`);
    console.log(`   Database: ${databaseId}`);
    if (dryRun) console.log('   🧪 وضع المحاكاة (DRY-RUN)');
    if (verifyOnly) console.log('   🔍 وضع التحقق فقط');
    if (migrateOnly) console.log('   🔄 وضع النقل فقط');

    try {
        await db.get(databaseId);
        console.log('   ✅ قاعدة البيانات موجودة\n');

        if (verifyOnly) {
            await verifyCollection();
        } else {
            if (!migrateOnly) {
                await createBlacklistCollection();
                await addShiftNotesBlacklistIndex();
            }
            await migrateFromShiftNotes();
            await verifyCollection();
        }
    } catch (e) {
        console.error('\n💥 خطأ عام:', e.message);
        if (e.code) console.error(`   كود الخطأ: ${e.code}`);
        process.exit(1);
    }

    console.log('\n✅ اكتملت العملية بنجاح!\n');
}

main();
