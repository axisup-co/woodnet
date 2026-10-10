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
