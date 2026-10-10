import bcrypt from 'bcryptjs';
import { query } from '../db/pool.js';
import { HttpError } from '../middleware/errorHandler.js';
import { signToken } from '../utils/jwt.js';

const ROUNDS = 10;

export async function register({ username, email, password, fullName }) {
  const exists = await query('SELECT 1 FROM users WHERE username = $1 OR email = $2 LIMIT 1', [username, email]);
  if (exists.rowCount) throw new HttpError(409, 'conflict', 'username or email already in use');
  const hash = await bcrypt.hash(password, ROUNDS);
  const { rows } = await query(
    `INSERT INTO users (username, email, password_hash, full_name)
     VALUES ($1, $2, $3, $4)
     RETURNING id, username, email, full_name, avatar_url, created_at`,
    [username, email, hash, fullName || null]
  );
  const user = rows[0];
  return { user, token: signToken({ sub: user.id, username: user.username }) };
}

export async function login({ email, password }) {
  const { rows } = await query(
    'SELECT id, username, email, password_hash, full_name, avatar_url FROM users WHERE email = $1 LIMIT 1',
    [email]
  );
  const user = rows[0];
  if (!user) throw new HttpError(401, 'unauthorized', 'invalid credentials');
  const ok = await bcrypt.compare(password, user.password_hash);
  if (!ok) throw new HttpError(401, 'unauthorized', 'invalid credentials');
  delete user.password_hash;
  return { user, token: signToken({ sub: user.id, username: user.username }) };
}
