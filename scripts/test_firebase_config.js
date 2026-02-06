const fs = require('fs');
const https = require('https');

const GOOGLE_SERVICES_PATH = process.argv[2] || 'mobile/android/app/google-services.json';

console.log('═══════════════════════════════════════════════════════');
console.log('🔥 Firebase Configuration Test');
console.log('═══════════════════════════════════════════════════════\n');

// 1. Check if file exists
console.log('1️⃣  Checking google-services.json...');
if (!fs.existsSync(GOOGLE_SERVICES_PATH)) {
  console.error('❌ File not found:', GOOGLE_SERVICES_PATH);
  process.exit(1);
}
console.log('   ✅ File exists\n');

// 2. Parse JSON
let config;
try {
  const content = fs.readFileSync(GOOGLE_SERVICES_PATH, 'utf8');
  config = JSON.parse(content);
  console.log('2️⃣  Parsing JSON...');
  console.log('   ✅ Valid JSON\n');
} catch (e) {
  console.error('❌ Invalid JSON:', e.message);
  process.exit(1);
}

// 3. Validate structure
console.log('3️⃣  Validating structure...');
const required = ['project_info', 'client'];
const missing = required.filter(k => !config[k]);
if (missing.length > 0) {
  console.error('❌ Missing required fields:', missing.join(', '));
  process.exit(1);
}
console.log('   ✅ Structure valid\n');

// 4. Extract info
console.log('4️⃣  Project Info:');
const projectInfo = config.project_info;
console.log('   📦 Project ID:', projectInfo.project_id);
console.log('   🔢 Project Number:', projectInfo.project_number);
console.log('   🗄️  Storage Bucket:', projectInfo.storage_bucket || 'N/A');
console.log('');

// 5. Check client config
console.log('5️⃣  Client Config:');
const client = config.client[0];
if (!client) {
  console.error('❌ No client configuration found');
  process.exit(1);
}
const clientInfo = client.client_info;
console.log('   📱 App ID:', clientInfo.mobilesdk_app_id);
console.log('   📦 Package Name:', clientInfo.android_client_info?.package_name);
console.log('');

// 6. Check API Key
console.log('6️⃣  API Key:');
const apiKey = client.api_key?.[0]?.current_key;
if (!apiKey) {
  console.error('❌ No API key found');
  process.exit(1);
}
console.log('   🔑 Key:', apiKey.substring(0, 20) + '...');
console.log('');

// 7. Check OAuth clients
console.log('7️⃣  OAuth Clients:');
const oauthClients = client.oauth_client || [];
oauthClients.forEach((oc, i) => {
  const type = oc.client_type === 1 ? 'Android' : oc.client_type === 3 ? 'Web' : 'Other';
  console.log(`   ${i + 1}. ${type}: ${oc.client_id.substring(0, 30)}...`);
  if (oc.android_info) {
    console.log(`      SHA-1: ${oc.android_info.certificate_hash}`);
  }
});
console.log('');

// 8. Test Firebase connection
console.log('8️⃣  Testing Firebase connection...');
const testUrl = `https://firebaseinstallations.googleapis.com/v1/projects/${projectInfo.project_id}/installations`;

const options = {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'x-goog-api-key': apiKey,
  },
  timeout: 10000,
};

const req = https.request(testUrl, options, (res) => {
  if (res.statusCode === 400 || res.statusCode === 401 || res.statusCode === 403) {
    // These errors mean Firebase received our request (connection works)
    console.log('   ✅ Firebase API reachable (auth required for full test)');
  } else if (res.statusCode >= 200 && res.statusCode < 300) {
    console.log('   ✅ Firebase API connected successfully');
  } else {
    console.log('   ⚠️  Unexpected status:', res.statusCode);
  }
  
  printSummary(projectInfo, clientInfo, apiKey);
});

req.on('error', (e) => {
  console.log('   ❌ Connection failed:', e.message);
  printSummary(projectInfo, clientInfo, apiKey);
});

req.on('timeout', () => {
  console.log('   ⚠️  Connection timeout');
  req.destroy();
  printSummary(projectInfo, clientInfo, apiKey);
});

req.write(JSON.stringify({
  fid: 'test-fid',
  appId: clientInfo.mobilesdk_app_id,
  authVersion: 'FIS_v2',
  sdkVersion: 'test',
}));

req.end();

function printSummary(projectInfo, clientInfo, apiKey) {
  console.log('\n═══════════════════════════════════════════════════════');
  console.log('📋 Summary');
  console.log('═══════════════════════════════════════════════════════');
  console.log('✅ google-services.json is valid');
  console.log('✅ Project:', projectInfo.project_id);
  console.log('✅ Package:', clientInfo.android_client_info?.package_name);
  console.log('✅ API Key present');
  console.log('═══════════════════════════════════════════════════════');
  console.log('\n🔗 Firebase Console:');
  console.log(`   https://console.firebase.google.com/project/${projectInfo.project_id}`);
  console.log('\n📱 To enable FCM:');
  console.log('   1. Go to Firebase Console → Project Settings');
  console.log('   2. Cloud Messaging tab → Enable Cloud Messaging API');
  console.log('   3. Generate Server Key or Service Account');
  console.log('═══════════════════════════════════════════════════════\n');
}
