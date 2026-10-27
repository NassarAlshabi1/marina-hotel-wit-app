const { Client, Databases } = require('node-appwrite');

const client = new Client();

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const API_KEY = process.env.APPWRITE_API_KEY || process.argv[2];
const DATABASE_ID = 'hotel_db';

if (!API_KEY) {
  console.error('❌ يرجى توفير API Key كـ argument أو APPWRITE_API_KEY env');
  process.exit(1);
}

client
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(API_KEY);

const databases = new Databases(client);

async function addDiscountStartDateField() {
  console.log('🔄 إضافة حقل discountStartDate إلى جدول bookings...\n');
  
  try {
    const result = await databases.createStringAttribute(
      DATABASE_ID,
      'bookings',
      'discountStartDate',
      255,
      false,
      null,
      false
    );
    
    console.log('✅ تم إضافة حقل discountStartDate بنجاح!');
    console.log('📋 التفاصيل:');
    console.log(`   - الاسم: discountStartDate`);
    console.log(`   - النوع: string`);
    console.log(`   - الحجم: 255`);
    console.log(`   - إجباري: لا`);
    console.log(`   - الحالة: ${result.status}`);
    
  } catch (error) {
    if (error.code === 409) {
      console.log('⚠️ حقل discountStartDate موجود مسبقاً');
    } else {
      console.error('❌ خطأ:', error.message);
      throw error;
    }
  }
}

async function verifyField() {
  console.log('\n🔍 التحقق من الحقل...');
  
  try {
    const attrs = await databases.listAttributes(DATABASE_ID, 'bookings');
    const discountField = attrs.attributes.find(a => a.key === 'discountStartDate');
    
    if (discountField) {
      console.log('✅ الحقل موجود ومُفعّل');
      console.log(`   - النوع: ${discountField.type}`);
      console.log(`   - الحالة: ${discountField.status}`);
    } else {
      console.log('❌ الحقل غير موجود!');
    }
  } catch (error) {
    console.error('❌ خطأ في التحقق:', error.message);
  }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('   إضافة حقل تاريخ بدء التخفيض - discountStartDate');
  console.log('═══════════════════════════════════════════════════════════\n');
  
  await addDiscountStartDateField();
  
  console.log('\n⏳ انتظار تفعيل الحقل (5 ثواني)...');
  await new Promise(r => setTimeout(r, 5000));
  
  await verifyField();
  
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('✅ اكتمل!');
  console.log('═══════════════════════════════════════════════════════════');
}

main().catch(console.error);
