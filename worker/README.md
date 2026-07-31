# Marina Hotel — Cloudflare Worker API + Flutter Sync Client

## البنية

```
/
  worker/                    ← Cloudflare Worker (TypeScript)
    src/
      index.ts               ← Main router + rate limiting + CORS
      auth.ts                ← JWT auth + middleware + password hashing
      sync.ts                ← Pull/Push sync + conflict resolution
      database.ts            ← D1 queries + idempotency + vector clocks
      storage.ts             ← R2 file upload/download/delete
    schema.sql               ← D1 database schema (7 tables + indexes)
    wrangler.toml            ← Cloudflare config
    package.json
    tsconfig.json

  flutter/                   ← Flutter sync client (Dart)
    sync/
      api_client.dart        ← HTTP client (auth, sync, files)
      sync_repository.dart   ← Sync logic with Drift SQLite
```

## الإعداد

### 1. Cloudflare D1 Database

```bash
# Create D1 database
wrangler d1 create marina-hotel-db

# Apply schema
wrangler d1 execute marina-hotel-db --file=./worker/schema.sql

# Create first admin user (via API after deploy)
curl -X POST https://your-worker.workers.dev/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"your-password","role":"admin"}'
```

### 2. Cloudflare R2 Bucket

```bash
wrangler r2 bucket create marina-hotel-files
```

### 3. Deploy Worker

```bash
cd worker
npm install
wrangler deploy
```

### 4. Set JWT Secret

```bash
wrangler secret put JWT_SECRET
# Enter a strong random string
```

### 5. Flutter Integration

```dart
// Initialize
final apiClient = ApiClient(baseUrl: 'https://your-worker.workers.dev');
await apiClient.init();

// Login
await apiClient.login(username: 'admin', password: 'your-password');

// Create sync repository
final syncRepo = SyncRepository(apiClient: apiClient);

// Queue operations
await syncRepo.queueCreate(
  entity: 'bookings',
  localUuid: 'uuid-here',
  data: {'room_number': '101', 'guest_name': 'أحمد', ...},
  vectorClock: '{"dev1": 1}',
);

// Push to server
await syncRepo.pushChanges();

// Pull from server
await syncRepo.pullChanges(
  onApplyChange: (entity, data) async {
    // Apply remote change to your local Drift tables
    print('Received: $entity ${data['id']}');
  },
);

// Full sync (push + pull)
await syncRepo.fullSync(
  onApplyChange: (entity, data) async {
    // ...
  },
);

// File operations
final meta = await syncRepo.uploadFile(File('/path/to/image.jpg'));
final bytes = await syncRepo.downloadFile(meta.data!.id);
await syncRepo.deleteFile(meta.data!.id);
```

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/auth/register` | — | Register first admin user |
| POST | `/api/auth/login` | — | Login → JWT token |
| GET | `/api/sync/pull?cursor=0&limit=200` | ✅ | Delta sync pull |
| POST | `/api/sync/push` | ✅ | Batch push outbox operations |
| GET | `/api/sync/log?limit=50` | ✅ | View sync audit log |
| GET | `/api/sync/conflicts?limit=50` | ✅ | View sync conflicts |
| POST | `/api/files/upload` | ✅ | Upload file to R2 |
| GET | `/api/files/:id` | ✅ | Download file from R2 |
| DELETE | `/api/files/:id` | ✅ | Delete file from R2 |
| GET | `/health` | — | Health check |

## Security

- **JWT Authentication**: HMAC-SHA256 self-signed tokens
- **Password Hashing**: PBKDF2 (100K iterations, SHA-256)
- **Rate Limiting**: KV-based per-IP limiting (100 req/min default)
- **SQL Injection**: All queries use parameterized D1 prepared statements
- **Validation**: All push operations validated server-side
- **CORS**: Configurable origin
- **Idempotency**: Duplicate operations rejected via `idempotencyKey`
- **File Upload**: MIME type whitelist + 50MB max size

## Conflict Resolution

- **Strategy**: Last Write Wins (LWW) + Vector Clock detection
- **Concurrent edits**: Detected via vector clock comparison
- **Conflicts logged**: Saved to `sync_conflicts` table with both payloads
- **Resolution**: Higher `updated_at` wins; loser's data preserved in conflict log
