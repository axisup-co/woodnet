#!/data/data/com.termux/files/usr/bin/bash
set -e
cd ~/woodnet/server

# ---------- src/middleware/errorHandler.js ----------
cat > src/middleware/errorHandler.js << 'EOF'
import { log } from '../utils/logger.js';

export class HttpError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function errorHandler(err, _req, res, _next) {
  const status = err.status || 500;
  if (status >= 500) log.error(err.message, err.stack);
  res.status(status).json({
    error: err.code || 'internal_error',
    message: status >= 500 ? 'internal server error' : err.message,
  });
}
EOF

# ---------- src/middleware/auth.js ----------
cat > src/middleware/auth.js << 'EOF'
import { verifyToken } from '../utils/jwt.js';
import { HttpError } from './errorHandler.js';

function parse(req) {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') ? h.slice(7) : null;
}

export function requireAuth(req, _res, next) {
  const token = parse(req);
  if (!token) return next(new HttpError(401, 'unauthorized', 'missing token'));
  try {
    const p = verifyToken(token);
    req.user = { id: p.sub, username: p.username };
    next();
  } catch {
    next(new HttpError(401, 'unauthorized', 'invalid token'));
  }
}

export function optionalAuth(req, _res, next) {
  const token = parse(req);
  if (token) {
    try {
      const p = verifyToken(token);
      req.user = { id: p.sub, username: p.username };
    } catch { /* ignore */ }
  }
  next();
}
EOF

# ---------- src/middleware/role.js ----------
cat > src/middleware/role.js << 'EOF'
import { query } from '../db/pool.js';
import { HttpError } from './errorHandler.js';

const RANK = { user: 0, moderator: 1, admin: 2, owner: 3 };

export function requireRole(min) {
  return async (req, _res, next) => {
    try {
      const { rows } = await query('SELECT role FROM users WHERE id = $1', [req.user.id]);
      if (!rows.length) throw new HttpError(401, 'unauthorized', 'user not found');
      const current = rows[0].role || 'user';
      if ((RANK[current] ?? 0) < (RANK[min] ?? 99)) {
        throw new HttpError(403, 'forbidden', `requires ${min}`);
      }
      req.role = current;
      next();
    } catch (e) { next(e); }
  };
}
EOF

# ---------- src/middleware/validate.js ----------
cat > src/middleware/validate.js << 'EOF'
import { HttpError } from './errorHandler.js';

export function validate(schema, source = 'body') {
  return (req, _res, next) => {
    const r = schema.safeParse(req[source]);
    if (!r.success) {
      const issue = r.error.issues[0];
      return next(new HttpError(400, 'validation_error', `${issue.path.join('.')}: ${issue.message}`));
    }
    req[source] = r.data;
    next();
  };
}
EOF

# ---------- src/services/authService.js ----------
cat > src/services/authService.js << 'EOF'
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
EOF

# ---------- src/services/postService.js ----------
cat > src/services/postService.js << 'EOF'
import { query, tx } from '../db/pool.js';
import { HttpError } from '../middleware/errorHandler.js';

export async function createPost({ authorId, content, mediaUrl, visibility = 'public' }) {
  if (!content && !mediaUrl) throw new HttpError(400, 'validation_error', 'post is empty');
  const { rows } = await query(
    `INSERT INTO posts (author_id, content, media_url, visibility)
     VALUES ($1, $2, $3, $4) RETURNING *`,
    [authorId, content || null, mediaUrl || null, visibility]
  );
  return rows[0];
}

export async function deletePost({ postId, userId }) {
  const { rowCount } = await query('DELETE FROM posts WHERE id = $1 AND author_id = $2', [postId, userId]);
  if (!rowCount) throw new HttpError(404, 'not_found', 'post not found');
}

export async function getFeed({ userId, limit = 20, cursor }) {
  const params = [userId, limit];
  let clause = '';
  if (cursor) { clause = 'AND p.created_at < $3'; params.push(cursor); }
  const { rows } = await query(
    `SELECT p.id, p.author_id, p.content, p.media_url, p.visibility, p.created_at,
            u.username AS author_username, u.full_name AS author_full_name, u.avatar_url AS author_avatar,
            (SELECT COUNT(*)::int FROM likes l WHERE l.post_id = p.id) AS like_count,
            (SELECT COUNT(*)::int FROM comments c WHERE c.post_id = p.id) AS comment_count,
            EXISTS (SELECT 1 FROM likes l WHERE l.post_id = p.id AND l.user_id = $1) AS liked_by_me
       FROM posts p JOIN users u ON u.id = p.author_id
      WHERE (p.visibility = 'public' OR p.author_id = $1
             OR p.author_id IN (
               SELECT CASE WHEN requester_id = $1 THEN addressee_id ELSE requester_id END
                 FROM friendships
                WHERE status = 'accepted' AND (requester_id = $1 OR addressee_id = $1)))
        ${clause}
      ORDER BY p.created_at DESC LIMIT $2`,
    params
  );
  const nextCursor = rows.length === limit ? rows[rows.length - 1].created_at : null;
  return { items: rows, nextCursor };
}

export async function likePost({ postId, userId }) {
  return tx(async (client) => {
    const p = await client.query('SELECT author_id FROM posts WHERE id = $1', [postId]);
    if (!p.rowCount) throw new HttpError(404, 'not_found', 'post not found');
    await client.query('INSERT INTO likes (user_id, post_id) VALUES ($1,$2) ON CONFLICT DO NOTHING', [userId, postId]);
    return { postAuthorId: p.rows[0].author_id };
  });
}

export async function unlikePost({ postId, userId }) {
  await query('DELETE FROM likes WHERE user_id = $1 AND post_id = $2', [userId, postId]);
}

export async function listComments({ postId }) {
  const { rows } = await query(
    `SELECT c.id, c.content, c.created_at, u.id AS author_id, u.username, u.full_name, u.avatar_url
       FROM comments c JOIN users u ON u.id = c.author_id
      WHERE c.post_id = $1 ORDER BY c.created_at ASC LIMIT 200`,
    [postId]
  );
  return rows;
}

export async function addComment({ postId, authorId, content }) {
  const { rows } = await query(
    `INSERT INTO comments (post_id, author_id, content) VALUES ($1,$2,$3)
     RETURNING id, content, created_at,
       (SELECT username FROM users WHERE id = $2) AS username,
       (SELECT avatar_url FROM users WHERE id = $2) AS avatar_url`,
    [postId, authorId, content]
  );
  const owner = await query('SELECT author_id FROM posts WHERE id = $1', [postId]);
  return { comment: rows[0], postAuthorId: owner.rows[0]?.author_id };
}
EOF

# ---------- src/services/friendService.js ----------
cat > src/services/friendService.js << 'EOF'
import { query, tx } from '../db/pool.js';
import { HttpError } from '../middleware/errorHandler.js';

export async function sendRequest({ requesterId, addresseeId }) {
  if (requesterId === addresseeId) throw new HttpError(400, 'validation_error', 'cannot friend yourself');
  return tx(async (client) => {
    const ex = await client.query(
      `SELECT id, status, requester_id FROM friendships
        WHERE (requester_id = $1 AND addressee_id = $2)
           OR (requester_id = $2 AND addressee_id = $1)`,
      [requesterId, addresseeId]
    );
    if (ex.rowCount) {
      const row = ex.rows[0];
      if (row.status === 'accepted') throw new HttpError(409, 'conflict', 'already friends');
      if (row.requester_id === addresseeId) {
        await client.query(`UPDATE friendships SET status='accepted', updated_at=now() WHERE id=$1`, [row.id]);
        return { status: 'accepted' };
      }
      throw new HttpError(409, 'conflict', 'request already pending');
    }
    await client.query(
      `INSERT INTO friendships (requester_id, addressee_id, status) VALUES ($1,$2,'pending')`,
      [requesterId, addresseeId]
    );
    return { status: 'pending' };
  });
}

export async function respondRequest({ userId, requestId, accept }) {
  const { rows, rowCount } = await query(
    `UPDATE friendships SET status = $3, updated_at = now()
      WHERE id = $1 AND addressee_id = $2 AND status = 'pending'
      RETURNING requester_id, addressee_id`,
    [requestId, userId, accept ? 'accepted' : 'rejected']
  );
  if (!rowCount) throw new HttpError(404, 'not_found', 'request not found');
  return rows[0];
}

export async function listFriends(userId) {
  const { rows } = await query(
    `SELECT u.id, u.username, u.full_name, u.avatar_url
       FROM friendships f
       JOIN users u ON u.id = CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END
      WHERE f.status = 'accepted' AND (f.requester_id = $1 OR f.addressee_id = $1)
      ORDER BY u.username`,
    [userId]
  );
  return rows;
}

export async function listRequests(userId) {
  const { rows } = await query(
    `SELECT f.id, f.created_at, u.id AS requester_id, u.username, u.full_name, u.avatar_url
       FROM friendships f JOIN users u ON u.id = f.requester_id
      WHERE f.addressee_id = $1 AND f.status = 'pending'
      ORDER BY f.created_at DESC`,
    [userId]
  );
  return rows;
}
EOF

# ---------- src/services/messageService.js ----------
cat > src/services/messageService.js << 'EOF'
import { query, tx } from '../db/pool.js';
import { HttpError } from '../middleware/errorHandler.js';

export async function getOrCreateConversation(userA, userB) {
  return tx(async (client) => {
    const ex = await client.query(
      `SELECT c.id FROM conversations c
        JOIN conversation_members m1 ON m1.conversation_id = c.id AND m1.user_id = $1
        JOIN conversation_members m2 ON m2.conversation_id = c.id AND m2.user_id = $2
       LIMIT 1`,
      [userA, userB]
    );
    if (ex.rowCount) return ex.rows[0].id;
    const { rows } = await client.query('INSERT INTO conversations DEFAULT VALUES RETURNING id');
    const id = rows[0].id;
    await client.query(
      'INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1,$2),($1,$3)',
      [id, userA, userB]
    );
    return id;
  });
}

export async function listConversations(userId) {
  const { rows } = await query(
    `SELECT c.id, c.last_message_at,
            (SELECT json_build_object('id', u.id, 'username', u.username, 'full_name', u.full_name, 'avatar_url', u.avatar_url)
               FROM conversation_members cm JOIN users u ON u.id = cm.user_id
              WHERE cm.conversation_id = c.id AND cm.user_id <> $1 LIMIT 1) AS peer,
            (SELECT body FROM messages m WHERE m.conversation_id = c.id ORDER BY m.created_at DESC LIMIT 1) AS last_message
       FROM conversations c
       JOIN conversation_members me ON me.conversation_id = c.id AND me.user_id = $1
      ORDER BY c.last_message_at DESC LIMIT 100`,
    [userId]
  );
  return rows;
}

export async function listMessages({ conversationId, userId, limit = 50, before }) {
  const member = await query('SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2', [conversationId, userId]);
  if (!member.rowCount) throw new HttpError(403, 'forbidden', 'not a member');
  const params = [conversationId, limit];
  let clause = '';
  if (before) { clause = 'AND created_at < $3'; params.push(before); }
  const { rows } = await query(
    `SELECT id, sender_id, body, created_at, read_at FROM messages
      WHERE conversation_id = $1 ${clause}
      ORDER BY created_at DESC LIMIT $2`,
    params
  );
  return rows.reverse();
}

export async function sendMessage({ conversationId, senderId, body }) {
  return tx(async (client) => {
    const m = await client.query('SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2', [conversationId, senderId]);
    if (!m.rowCount) throw new HttpError(403, 'forbidden', 'not a member');
    const { rows } = await client.query(
      `INSERT INTO messages (conversation_id, sender_id, body)
       VALUES ($1,$2,$3) RETURNING id, sender_id, body, created_at`,
      [conversationId, senderId, body]
    );
    await client.query('UPDATE conversations SET last_message_at = now() WHERE id = $1', [conversationId]);
    const peers = await client.query(
      'SELECT user_id FROM conversation_members WHERE conversation_id = $1 AND user_id <> $2',
      [conversationId, senderId]
    );
    return { message: rows[0], peerIds: peers.rows.map((r) => r.user_id) };
  });
}
EOF

# ---------- src/services/notificationService.js ----------
cat > src/services/notificationService.js << 'EOF'
import { query } from '../db/pool.js';

export async function createNotification({ userId, type, actorId, entityId, payload }) {
  if (userId === actorId && type !== 'system') return null;
  const { rows } = await query(
    `INSERT INTO notifications (user_id, type, actor_id, entity_id, payload)
     VALUES ($1,$2,$3,$4,$5) RETURNING *`,
    [userId, type, actorId || null, entityId || null, payload || null]
  );
  return rows[0];
}

export async function listNotifications(userId, limit = 50) {
  const { rows } = await query(
    `SELECT n.*, u.username AS actor_username, u.avatar_url AS actor_avatar
       FROM notifications n LEFT JOIN users u ON u.id = n.actor_id
      WHERE n.user_id = $1 ORDER BY n.created_at DESC LIMIT $2`,
    [userId, limit]
  );
  return rows;
}

export async function markRead(userId, notificationId) {
  await query('UPDATE notifications SET read_at = now() WHERE id = $1 AND user_id = $2', [notificationId, userId]);
}
EOF

echo ""
echo "==================================================="
echo " BOOTSTRAP PART 2 COMPLETE"
echo " Middleware + Services created"
echo "==================================================="
find src/middleware src/services -type f | sort
echo ""
