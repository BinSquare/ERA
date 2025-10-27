# ERA Storage Proxy

The Storage Proxy allows sandboxed code running in ERA sessions to access Cloudflare's storage primitives (KV, D1, R2) in a namespaced, secure way.

## Overview

The Storage Proxy provides:
- **KV Storage**: Key-value storage for lightweight data
- **D1 Database**: SQL database for structured data
- **R2 Storage**: Object storage for files and binary data
- **Resource Registry**: Track and discover all created resources

## Architecture

```
┌─────────────────────────────────────────┐
│  Sandboxed Code (Python/JavaScript)     │
│  - Uses era_storage SDK                 │
│  - Makes HTTP requests via ERA_STORAGE_URL │
└─────────────┬───────────────────────────┘
              │ HTTP
              ▼
┌─────────────────────────────────────────┐
│  Storage Proxy API                      │
│  /api/storage/{type}/{namespace}/{key}  │
└─────────────┬───────────────────────────┘
              │
       ┌──────┴──────┬──────────┐
       ▼             ▼          ▼
   ┌─────┐      ┌─────┐    ┌─────┐
   │ KV  │      │ D1  │    │ R2  │
   └─────┘      └─────┘    └─────┘
       │             │          │
       └──────┬──────┴──────────┘
              ▼
   ┌──────────────────────┐
   │  Storage Registry    │
   │  (Tracks Resources)  │
   └──────────────────────┘
```

## Configuration

### 1. Update wrangler.toml

The storage bindings are already configured in `wrangler.toml`:

```toml
# R2 bucket for storage proxy
[[r2_buckets]]
binding = "ERA_R2"
bucket_name = "era-storage"

# KV namespace for storage proxy
[[kv_namespaces]]
binding = "ERA_KV"
id = "your_kv_namespace_id"

# D1 database for storage proxy
[[d1_databases]]
binding = "ERA_D1"
database_name = "era-storage"
database_id = "your_d1_database_id"

# Storage Registry Durable Object
[[durable_objects.bindings]]
name = "STORAGE_REGISTRY"
class_name = "StorageRegistry"
```

### 2. Set Storage URL (Optional)

For local development, the default URL is `http://host.docker.internal:8787`.
For production, set the environment variable:

```toml
[vars]
ERA_STORAGE_URL = "https://era-agent.your-subdomain.workers.dev"
```

## SDK Usage

### Python SDK

The Python SDK is automatically injected into every session as `era_storage.py`:

```python
import era_storage

# KV Storage
era_storage.kv.set("app1", "user:123", '{"name": "Alice"}')
data = era_storage.kv.get("app1", "user:123")
keys = era_storage.kv.list("app1", prefix="user:")
era_storage.kv.delete("app1", "user:123")

# D1 Database
era_storage.d1.exec("app1", "CREATE TABLE users (id INTEGER, name TEXT)")
era_storage.d1.exec("app1", "INSERT INTO users VALUES (?, ?)", [1, "Bob"])
users = era_storage.d1.query("app1", "SELECT * FROM users")

# R2 Storage
era_storage.r2.put("app1", "file.txt", b"Hello World!")
content = era_storage.r2.get("app1", "file.txt")
objects = era_storage.r2.list("app1", prefix="uploads/")
era_storage.r2.delete("app1", "file.txt")
```

### JavaScript SDK

The JavaScript SDK is also automatically injected as `era_storage.js`:

```javascript
const { KVStorage, D1Storage, R2Storage } = require('./era_storage.js');

// KV Storage
await KVStorage.set("app1", "user:123", JSON.stringify({name: "Alice"}));
const data = await KVStorage.get("app1", "user:123");
const keys = await KVStorage.list("app1", "user:");
await KVStorage.delete("app1", "user:123");

// D1 Database
await D1Storage.exec("app1", "CREATE TABLE users (id INTEGER, name TEXT)");
await D1Storage.exec("app1", "INSERT INTO users VALUES (?, ?)", [1, "Bob"]);
const users = await D1Storage.query("app1", "SELECT * FROM users");

// R2 Storage
await R2Storage.put("app1", "file.txt", "Hello World!");
const content = await R2Storage.get("app1", "file.txt");
const objects = await R2Storage.list("app1", "uploads/");
await R2Storage.delete("app1", "file.txt");
```

## Namespacing

Resources are isolated by namespace, allowing multiple "apps" to coexist:

```python
# App 1 resources
era_storage.kv.set("app1", "config", "...")
era_storage.d1.exec("app1", "CREATE TABLE users ...")

# App 2 resources
era_storage.kv.set("app2", "config", "...")
era_storage.d1.exec("app2", "CREATE TABLE users ...")

# Cross-namespace access is allowed
app1_config = era_storage.kv.get("app1", "config")
app2_config = era_storage.kv.get("app2", "config")
```

Internally, resources are stored with prefixes:
- **KV**: `{namespace}:{key}` → `app1:config`
- **D1**: Table names prefixed → `app1_users`
- **R2**: Path prefixed → `app1/file.txt`

## Resource Registry

Track and discover all created resources:

### List Resources

```bash
# List all resources
GET /api/resources/list

# Filter by type
GET /api/resources/list?type=kv

# Filter by namespace
GET /api/resources/list?namespace=app1

# Filter by key prefix
GET /api/resources/list?key_prefix=user:

# Pagination
GET /api/resources/list?limit=50&offset=100
```

Example response:

```json
{
  "resources": [
    {
      "type": "kv",
      "namespace": "app1",
      "key": "user:123",
      "created_at": "2025-10-25T10:30:00Z",
      "updated_at": "2025-10-25T11:00:00Z",
      "size": 45,
      "metadata": {"version": 1}
    },
    {
      "type": "d1",
      "namespace": "app1",
      "key": "users",
      "created_at": "2025-10-25T10:35:00Z",
      "updated_at": "2025-10-25T10:35:00Z"
    }
  ],
  "total": 25,
  "offset": 0,
  "limit": 100,
  "has_more": false
}
```

### Get Statistics

```bash
GET /api/resources/stats
```

Example response:

```json
{
  "total": 42,
  "by_type": {
    "kv": 15,
    "d1": 3,
    "r2": 24,
    "do": 0
  },
  "by_namespace": {
    "app1": 20,
    "app2": 15,
    "shared": 7
  },
  "total_size": 1048576
}
```

## Direct API Access

You can also access the storage proxy directly via HTTP:

### KV Operations

```bash
# Set value
curl -X PUT http://localhost:8787/api/storage/kv/app1/mykey \
  -H "Content-Type: application/json" \
  -d '{"value": "Hello", "metadata": {"version": 1}}'

# Get value
curl http://localhost:8787/api/storage/kv/app1/mykey

# List keys
curl "http://localhost:8787/api/storage/kv/app1?prefix=user:&limit=100"

# Delete key
curl -X DELETE http://localhost:8787/api/storage/kv/app1/mykey
```

### D1 Operations

```bash
# Execute statement
curl -X POST http://localhost:8787/api/storage/d1/app1/exec \
  -H "Content-Type: application/json" \
  -d '{
    "sql": "CREATE TABLE users (id INTEGER, name TEXT)",
    "params": []
  }'

# Query
curl -X POST http://localhost:8787/api/storage/d1/app1/query \
  -H "Content-Type: application/json" \
  -d '{
    "sql": "SELECT * FROM users WHERE id = ?",
    "params": [123]
  }'
```

### R2 Operations

```bash
# Put object (base64 encoded content)
curl -X PUT http://localhost:8787/api/storage/r2/app1/file.txt \
  -H "Content-Type: application/json" \
  -d '{"content": "SGVsbG8gV29ybGQh", "metadata": {"type": "text"}}'

# Get object
curl http://localhost:8787/api/storage/r2/app1/file.txt

# List objects
curl "http://localhost:8787/api/storage/r2/app1?prefix=uploads/&limit=100"

# Delete object
curl -X DELETE http://localhost:8787/api/storage/r2/app1/file.txt
```

## Use Cases

### 1. User Data Persistence

```python
import era_storage
import json

# Save user preferences
prefs = {"theme": "dark", "lang": "en"}
era_storage.kv.set("myapp", f"user:{user_id}:prefs", json.dumps(prefs))

# Load user preferences
prefs_json = era_storage.kv.get("myapp", f"user:{user_id}:prefs")
prefs = json.loads(prefs_json)
```

### 2. Application Database

```python
import era_storage

# Initialize database
era_storage.d1.exec("myapp", """
  CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    completed BOOLEAN DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )
""")

# Add task
era_storage.d1.exec("myapp",
  "INSERT INTO tasks (title) VALUES (?)",
  ["Finish documentation"])

# Query tasks
tasks = era_storage.d1.query("myapp", "SELECT * FROM tasks WHERE completed = 0")
print(f"Pending tasks: {len(tasks)}")
```

### 3. File Storage

```python
import era_storage

# Upload user avatar
with open("avatar.jpg", "rb") as f:
    image_data = f.read()
    era_storage.r2.put("myapp", f"avatars/{user_id}.jpg", image_data)

# Download avatar
avatar_data = era_storage.r2.get("myapp", f"avatars/{user_id}.jpg")
with open("downloaded_avatar.jpg", "wb") as f:
    f.write(avatar_data)
```

### 4. Cross-App Data Sharing

```python
import era_storage

# App1 writes shared config
era_storage.kv.set("shared", "api_key", "sk-...")

# App2 reads shared config
api_key = era_storage.kv.get("shared", "api_key")
```

## Security Considerations

1. **Namespace Isolation**: While namespaces provide logical separation, they don't enforce security boundaries. Any code can access any namespace.

2. **No Authentication**: The storage proxy doesn't implement authentication. It's designed for single-user/single-tenant deployments.

3. **Resource Cleanup**: Remember to clean up resources when done to avoid accumulation.

4. **Rate Limiting**: Cloudflare's storage primitives have rate limits. Design your code accordingly.

## Testing

Run the test suite to verify storage proxy functionality:

```bash
# Full test suite
./tests/test-storage.sh

# Simple quick test
./tests/test-storage-simple.sh
```

## Deployment

### Create Required Resources

```bash
# Create R2 bucket
wrangler r2 bucket create era-storage

# Create KV namespace
wrangler kv:namespace create "ERA_KV"

# Create D1 database
wrangler d1 create era-storage

# Update wrangler.toml with the IDs from above commands
```

### Deploy Worker

```bash
cd cloudflare
npm run build
wrangler deploy
```

## Troubleshooting

### VM can't reach storage proxy

**Problem**: SDK requests fail with connection errors.

**Solution**: Ensure `ERA_STORAGE_URL` is set correctly:
- Local: `http://host.docker.internal:8787`
- Production: Your worker's public URL

### Resources not showing in registry

**Problem**: Created resources don't appear in `/api/resources/list`.

**Solution**: The registry is automatically updated when using SDK methods. If using direct API calls, the registry should also be updated automatically.

### D1 table name conflicts

**Problem**: Table names collide across namespaces.

**Solution**: Tables are automatically prefixed with `{namespace}_`. Access them through the SDK which handles this automatically.

## API Reference

### Storage Proxy Endpoints

- `GET /api/storage/kv/{namespace}/{key}` - Get KV value
- `PUT /api/storage/kv/{namespace}/{key}` - Set KV value
- `DELETE /api/storage/kv/{namespace}/{key}` - Delete KV key
- `GET /api/storage/kv/{namespace}` - List KV keys

- `POST /api/storage/d1/{namespace}/query` - Execute D1 query
- `POST /api/storage/d1/{namespace}/exec` - Execute D1 statement

- `GET /api/storage/r2/{namespace}/{key}` - Get R2 object
- `PUT /api/storage/r2/{namespace}/{key}` - Put R2 object
- `DELETE /api/storage/r2/{namespace}/{key}` - Delete R2 object
- `GET /api/storage/r2/{namespace}` - List R2 objects

### Resource Registry Endpoints

- `GET /api/resources/list` - List resources (supports query params: type, namespace, key_prefix, limit, offset)
- `GET /api/resources/stats` - Get resource statistics
- `POST /api/resources/register` - Register a resource
- `DELETE /api/resources/unregister` - Unregister a resource

## Examples

See `tests/test-storage.sh` for comprehensive examples of all storage operations.
