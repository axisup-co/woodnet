#!/data/data/com.termux/files/usr/bin/bash
set -e
cd ~/woodnet/server
mkdir -p src/{config,db/migrations,middleware,routes,services,sockets,utils} uploads

# ---------- package.json ----------
cat > package.json << 'EOF'
{
  "name": "woodnet-server",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "node --watch src/index.js",
    "start": "node src/index.js",
    "migrate": "psql $DATABASE_URL -f src/db/schema.sql && psql $DATABASE_URL -f src/db/migrations/002_admin.sql",
    "seed:admin": "node src/db/seed_admin.js"
  },
  "dependencies": {
    "bcryptjs": "^2.4.3",
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.19.2",
    "express-rate-limit": "^7.4.0",
    "helmet": "^7.1.0",
    "jsonwebtoken": "^9.0.2",
    "multer": "^1.4.5-lts.1",
    "pg": "^8.12.0",
    "socket.io": "^4.7.5",
    "uuid": "^10.0.0",
    "zod": "^3.23.8"
  }
}
EOF

# ---------- .env ----------
JWT_SECRET=$(openssl rand -hex 32)
cat > .env << EOF
PORT=4000
DATABASE_URL=postgres://woodnet:woodnet@localhost:5432/woodnet
REDIS_URL=redis://localhost:6379
JWT_SECRET=$JWT_SECRET
JWT_EXPIRES=7d
UPLOAD_DIR=./uploads
CORS_ORIGIN=http://localhost:5173
LOG_LEVEL=info
EOF

cat > .env.example << 'EOF'
PORT=4000
DATABASE_URL=postgres://woodnet:woodnet@localhost:5432/woodnet
REDIS_URL=redis://localhost:6379
JWT_SECRET=replace-me
JWT_EXPIRES=7d
UPLOAD_DIR=./uploads
CORS_ORIGIN=http://localhost:5173
LOG_LEVEL=info
EOF

# ---------- src/config/index.js ----------
cat > src/config/index.js << 'EOF'
import 'dotenv/config';

function required(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

export const config = {
  port: Number(process.env.PORT || 4000),
  databaseUrl: required('DATABASE_URL'),
  redisUrl: process.env.REDIS_URL || 'redis://localhost:6379',
  jwtSecret: required('JWT_SECRET'),
  jwtExpires: process.env.JWT_EXPIRES || '7d',
  uploadDir: process.env.UPLOAD_DIR || './uploads',
  corsOrigin: process.env.CORS_ORIGIN || 'http://localhost:5173',
};
EOF

# ---------- src/utils/logger.js ----------
cat > src/utils/logger.js << 'EOF'
const levels = ['debug', 'info', 'warn', 'error'];
const currentLevel = process.env.LOG_LEVEL || 'info';
const ts = () => new Date().toISOString();

function emit(level, msg, meta) {
  if (levels.indexOf(level) < levels.indexOf(currentLevel)) return;
  const line = `[${ts()}] ${level.toUpperCase()} ${msg}`;
  if (meta !== undefined) (level === 'error' ? console.error : console.log)(line, meta);
  else (level === 'error' ? console.error : console.log)(line);
}

export const log = {
  debug: (m, x) => emit('debug', m, x),
  info: (m, x) => emit('info', m, x),
  warn: (m, x) => emit('warn', m, x),
  error: (m, x) => emit('error', m, x),
};
EOF

# ---------- src/utils/jwt.js ----------
cat > src/utils/jwt.js << 'EOF'
import jwt from 'jsonwebtoken';
import { config } from '../config/index.js';

export const signToken = (payload) => jwt.sign(payload, config.jwtSecret, { expiresIn: config.jwtExpires });
export const verifyToken = (token) => jwt.verify(token, config.jwtSecret);
EOF

# ---------- src/db/pool.js ----------
cat > src/db/pool.js << 'EOF'
import pg from 'pg';
import { config } from '../config/index.js';
import { log } from '../utils/logger.js';

export const pool = new pg.Pool({
  connectionString: config.databaseUrl,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

pool.on('error', (err) => log.error('pg pool error', err.message));

export async function query(text, params) {
  const start = Date.now();
  const res = await pool.query(text, params);
  const dur = Date.now() - start;
  if (dur > 100) log.warn('slow query', { text: text.slice(0, 80), dur });
  return res;
}

export async function tx(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const out = await fn(client);
    await client.query('COMMIT');
    return out;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}
EOF

# ---------- src/db/schema.sql ----------
cat > src/db/schema.sql << 'EOF'
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username VARCHAR(32) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  full_name VARCHAR(120),
  bio TEXT,
  avatar_url TEXT,
  cover_url TEXT,
  is_private BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

CREATE TABLE IF NOT EXISTS posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT,
  media_url TEXT,
  visibility VARCHAR(16) NOT NULL DEFAULT 'public',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_posts_author_created ON posts(author_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_created ON posts(created_at DESC);

CREATE TABLE IF NOT EXISTS likes (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);

CREATE TABLE IF NOT EXISTS comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_comments_post ON comments(post_id, created_at);

CREATE TABLE IF NOT EXISTS friendships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  addressee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(requester_id, addressee_id),
  CHECK (requester_id <> addressee_id)
);
CREATE INDEX IF NOT EXISTS idx_friendships_addressee ON friendships(addressee_id, status);
CREATE INDEX IF NOT EXISTS idx_friendships_requester ON friendships(requester_id, status);

CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_message_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS conversation_members (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id, created_at DESC);

CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(32) NOT NULL,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  entity_id UUID,
  payload JSONB,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id, created_at DESC);
EOF

# ---------- src/db/migrations/002_admin.sql ----------
cat > src/db/migrations/002_admin.sql << 'EOF'
ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(16) NOT NULL DEFAULT 'user';
DO $$ BEGIN
  ALTER TABLE users ADD CONSTRAINT users_role_chk CHECK (role IN ('user','moderator','admin','owner'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS audit_log (
  id BIGSERIAL PRIMARY KEY,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  action VARCHAR(64) NOT NULL,
  target_id UUID,
  meta JSONB,
  ip TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_log(actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_log(action, created_at DESC);

CREATE TABLE IF NOT EXISTS site_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
EOF

# ---------- src/db/seed_admin.js ----------
cat > src/db/seed_admin.js << 'EOF'
import bcrypt from 'bcryptjs';
import { randomBytes } from 'node:crypto';
import { query } from './pool.js';
import { log } from '../utils/logger.js';

const username = process.env.ADMIN_USERNAME || 'woodnet_admin';
const email = process.env.ADMIN_EMAIL || 'admin@woodnet.local';
const password = process.env.ADMIN_PASSWORD || randomBytes(18).toString('base64url');
const fullName = process.env.ADMIN_FULLNAME || 'WoodNet Owner';
const ROUNDS = 10;

async function main() {
  const hash = await bcrypt.hash(password, ROUNDS);
  const { rows } = await query(
    `INSERT INTO users (username, email, password_hash, full_name, role)
     VALUES ($1, $2, $3, $4, 'owner')
     ON CONFLICT (username) DO UPDATE
       SET email = EXCLUDED.email,
           password_hash = EXCLUDED.password_hash,
           role = 'owner'
     RETURNING id, username, email, role`,
    [username, email, hash, fullName]
  );
  const u = rows[0];
  await query(
    `INSERT INTO audit_log (actor_id, action, target_id, meta)
     VALUES ($1, 'admin_seed', $1, $2)`,
    [u.id, JSON.stringify({ source: 'seed_admin.js', role: 'owner' })]
  );
  console.log('\n================ ADMIN CREDENTIALS ================');
  console.log('  Username :', username);
  console.log('  Email    :', email);
  console.log('  Password :', password);
  console.log('  Role     : owner (full access)');
  console.log('===================================================');
  console.log('> Save this password now. It will not be printed again.\n');
  log.info('admin seeded', { id: u.id, username: u.username, role: u.role });
  process.exit(0);
}

main().catch((e) => { console.error(e); process.exit(1); });
EOF

echo ""
echo "==================================================="
echo " BOOTSTRAP PART 1 COMPLETE"
echo " Created files:"
find . -type f -not -path './node_modules/*' | sort
echo "==================================================="
echo " JWT_SECRET written to .env"
echo " Next: run bootstrap_part2.sh for middleware/services/routes"
echo ""
