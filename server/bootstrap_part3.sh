#!/data/data/com.termux/files/usr/bin/bash
set -e
cd ~/woodnet/server

# ---------- src/routes/auth.js ----------
cat > src/routes/auth.js << 'EOF'
import { Router } from 'express';
import { z } from 'zod';
import rateLimit from 'express-rate-limit';
import { validate } from '../middleware/validate.js';
import { requireAuth } from '../middleware/auth.js';
import * as authService from '../services/authService.js';
import { query } from '../db/pool.js';

const router = Router();
const authLimiter = rateLimit({ windowMs: 60000, max: 20, standardHeaders: true });

const registerSchema = z.object({
  username: z.string().min(3).max(32).regex(/^[a-zA-Z0-9_.]+$/),
  email: z.string().email(),
  password: z.string().min(8).max(128),
  fullName: z.string().max(120).optional(),
});
const loginSchema = z.object({ email: z.string().email(), password: z.string().min(1) });

router.post('/register', authLimiter, validate(registerSchema), async (req, res, next) => {
  try { res.status(201).json(await authService.register(req.body)); } catch (e) { next(e); }
});
router.post('/login', authLimiter, validate(loginSchema), async (req, res, next) => {
  try { res.json(await authService.login(req.body)); } catch (e) { next(e); }
});
router.get('/me', requireAuth, async (req, res, next) => {
  try {
    const { rows } = await query(
      `SELECT id, username, email, full_name, bio, avatar_url, cover_url, is_private, role, created_at
         FROM users WHERE id = $1`,
      [req.user.id]
    );
    res.json({ user: rows[0] });
  } catch (e) { next(e); }
});
export default router;
EOF

# ---------- src/routes/users.js ----------
cat > src/routes/users.js << 'EOF'
import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db/pool.js';
import { requireAuth, optionalAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { HttpError } from '../middleware/errorHandler.js';

const router = Router();
const searchSchema = z.object({ q: z.string().min(1).max(64), limit: z.coerce.number().min(1).max(50).default(20) });

router.get('/search', optionalAuth, async (req, res, next) => {
  try {
    const { q, limit } = searchSchema.parse(req.query);
    const { rows } = await query(
      `SELECT id, username, full_name, avatar_url FROM users
        WHERE username ILIKE $1 OR full_name ILIKE $1
        ORDER BY username LIMIT $2`,
      [`%${q}%`, limit]
    );
    res.json({ users: rows });
  } catch (e) { next(e); }
});

router.get('/:username', optionalAuth, async (req, res, next) => {
  try {
    const { rows } = await query(
      `SELECT id, username, full_name, bio, avatar_url, cover_url, is_private, created_at
         FROM users WHERE username = $1`,
      [req.params.username]
    );
    if (!rows.length) throw new HttpError(404, 'not_found', 'user not found');
    const user = rows[0];
    const [posts, stats] = await Promise.all([
      query(
        `SELECT p.id, p.content, p.media_url, p.created_at,
                (SELECT COUNT(*)::int FROM likes l WHERE l.post_id = p.id) AS like_count,
                (SELECT COUNT(*)::int FROM comments c WHERE c.post_id = p.id) AS comment_count
           FROM posts p WHERE p.author_id = $1 AND p.visibility = 'public'
          ORDER BY p.created_at DESC LIMIT 30`,
        [user.id]
      ),
      query(
        `SELECT
           (SELECT COUNT(*)::int FROM friendships WHERE status='accepted' AND (requester_id=$1 OR addressee_id=$1)) AS friend_count,
           (SELECT COUNT(*)::int FROM posts WHERE author_id=$1) AS post_count`,
        [user.id]
      ),
    ]);
    res.json({ user, posts: posts.rows, stats: stats.rows[0] });
  } catch (e) { next(e); }
});

const updateSchema = z.object({
  fullName: z.string().max(120).optional(),
  bio: z.string().max(500).optional(),
  avatarUrl: z.string().url().max(500).optional(),
  coverUrl: z.string().url().max(500).optional(),
  isPrivate: z.boolean().optional(),
});

router.patch('/me', requireAuth, validate(updateSchema), async (req, res, next) => {
  try {
    const fields = [];
    const values = [];
    let i = 1;
    for (const [k, col] of [['fullName','full_name'],['bio','bio'],['avatarUrl','avatar_url'],['coverUrl','cover_url'],['isPrivate','is_private']]) {
      if (req.body[k] !== undefined) { fields.push(`${col} = $${i++}`); values.push(req.body[k]); }
    }
    if (!fields.length) return res.json({ ok: true });
    values.push(req.user.id);
    const { rows } = await query(
      `UPDATE users SET ${fields.join(', ')} WHERE id = $${i}
       RETURNING id, username, full_name, bio, avatar_url, cover_url, is_private`,
      values
    );
    res.json({ user: rows[0] });
  } catch (e) { next(e); }
});
export default router;
EOF

# ---------- src/routes/posts.js ----------
cat > src/routes/posts.js << 'EOF'
import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import * as postService from '../services/postService.js';
import * as notif from '../services/notificationService.js';
import { emitToUser } from '../sockets/index.js';

const router = Router();
const createSchema = z.object({
  content: z.string().max(5000).optional(),
  mediaUrl: z.string().max(500).optional(),
  visibility: z.enum(['public', 'friends', 'private']).default('public'),
}).refine((v) => v.content || v.mediaUrl, { message: 'post is empty' });
const commentSchema = z.object({ content: z.string().min(1).max(2000) });

router.post('/', requireAuth, validate(createSchema), async (req, res, next) => {
  try { res.status(201).json({ post: await postService.createPost({ authorId: req.user.id, ...req.body }) }); } catch (e) { next(e); }
});

router.delete('/:id', requireAuth, async (req, res, next) => {
  try { await postService.deletePost({ postId: req.params.id, userId: req.user.id }); res.status(204).end(); } catch (e) { next(e); }
});

router.get('/feed', requireAuth, async (req, res, next) => {
  try {
    const limit = Math.min(Number(req.query.limit) || 20, 50);
    const cursor = req.query.cursor || null;
    res.json(await postService.getFeed({ userId: req.user.id, limit, cursor }));
  } catch (e) { next(e); }
});

router.post('/:id/like', requireAuth, async (req, res, next) => {
  try {
    const { postAuthorId } = await postService.likePost({ postId: req.params.id, userId: req.user.id });
    const io = req.app.get('io');
    const n = await notif.createNotification({ userId: postAuthorId, type: 'like', actorId: req.user.id, entityId: req.params.id });
    if (n) emitToUser(io, postAuthorId, 'notification:new', n);
    res.json({ ok: true });
  } catch (e) { next(e); }
});

router.delete('/:id/like', requireAuth, async (req, res, next) => {
  try { await postService.unlikePost({ postId: req.params.id, userId: req.user.id }); res.json({ ok: true }); } catch (e) { next(e); }
});

router.get('/:id/comments', requireAuth, async (req, res, next) => {
  try { res.json({ comments: await postService.listComments({ postId: req.params.id }) }); } catch (e) { next(e); }
});

router.post('/:id/comments', requireAuth, validate(commentSchema), async (req, res, next) => {
  try {
    const { comment, postAuthorId } = await postService.addComment({
      postId: req.params.id, authorId: req.user.id, content: req.body.content,
    });
    const io = req.app.get('io');
    const n = await notif.createNotification({
      userId: postAuthorId, type: 'comment', actorId: req.user.id, entityId: req.params.id,
      payload: { preview: req.body.content.slice(0, 120) },
    });
    if (n) emitToUser(io, postAuthorId, 'notification:new', n);
    res.status(201).json({ comment });
  } catch (e) { next(e); }
});
export default router;
EOF

# ---------- src/routes/friends.js ----------
cat > src/routes/friends.js << 'EOF'
import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import * as friendService from '../services/friendService.js';
import * as notif from '../services/notificationService.js';
import { emitToUser } from '../sockets/index.js';

const router = Router();
const sendSchema = z.object({ addresseeId: z.string().uuid() });
const respondSchema = z.object({ requestId: z.string().uuid(), accept: z.boolean() });

router.get('/', requireAuth, async (req, res, next) => {
  try { res.json({ friends: await friendService.listFriends(req.user.id) }); } catch (e) { next(e); }
});
router.get('/requests', requireAuth, async (req, res, next) => {
  try { res.json({ requests: await friendService.listRequests(req.user.id) }); } catch (e) { next(e); }
});
router.post('/request', requireAuth, validate(sendSchema), async (req, res, next) => {
  try {
    const result = await friendService.sendRequest({ requesterId: req.user.id, addresseeId: req.body.addresseeId });
    if (result.status === 'pending') {
      const n = await notif.createNotification({ userId: req.body.addresseeId, type: 'friend_request', actorId: req.user.id });
      if (n) emitToUser(req.app.get('io'), req.body.addresseeId, 'notification:new', n);
    }
    res.json(result);
  } catch (e) { next(e); }
});
router.post('/respond', requireAuth, validate(respondSchema), async (req, res, next) => {
  try {
    const row = await friendService.respondRequest({ userId: req.user.id, ...req.body });
    if (req.body.accept) {
      const n = await notif.createNotification({ userId: row.requester_id, type: 'friend_accept', actorId: req.user.id });
      if (n) emitToUser(req.app.get('io'), row.requester_id, 'notification:new', n);
    }
    res.json({ ok: true });
  } catch (e) { next(e); }
});
export default router;
EOF

# ---------- src/routes/messages.js ----------
cat > src/routes/messages.js << 'EOF'
import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import * as msgService from '../services/messageService.js';
import { emitToUser } from '../sockets/index.js';

const router = Router();
const convSchema = z.object({ peerId: z.string().uuid() });
const sendSchema = z.object({ body: z.string().min(1).max(4000) });

router.post('/conversation', requireAuth, validate(convSchema), async (req, res, next) => {
  try { res.json({ conversationId: await msgService.getOrCreateConversation(req.user.id, req.body.peerId) }); } catch (e) { next(e); }
});
router.get('/conversations', requireAuth, async (req, res, next) => {
  try { res.json({ conversations: await msgService.listConversations(req.user.id) }); } catch (e) { next(e); }
});
router.get('/conversations/:id/messages', requireAuth, async (req, res, next) => {
  try {
    const limit = Math.min(Number(req.query.limit) || 50, 100);
    const before = req.query.before || null;
    res.json({ messages: await msgService.listMessages({ conversationId: req.params.id, userId: req.user.id, limit, before }) });
  } catch (e) { next(e); }
});
router.post('/conversations/:id/messages', requireAuth, validate(sendSchema), async (req, res, next) => {
  try {
    const result = await msgService.sendMessage({ conversationId: req.params.id, senderId: req.user.id, body: req.body.body });
    const io = req.app.get('io');
    for (const peerId of result.peerIds) {
      emitToUser(io, peerId, 'message:new', { conversationId: req.params.id, message: result.message });
    }
    res.status(201).json({ message: result.message });
  } catch (e) { next(e); }
});
export default router;
EOF

# ---------- src/routes/notifications.js ----------
cat > src/routes/notifications.js << 'EOF'
import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import * as notif from '../services/notificationService.js';

const router = Router();
router.get('/', requireAuth, async (req, res, next) => {
  try { res.json({ notifications: await notif.listNotifications(req.user.id) }); } catch (e) { next(e); }
});
router.post('/:id/read', requireAuth, async (req, res, next) => {
  try { await notif.markRead(req.user.id, req.params.id); res.json({ ok: true }); } catch (e) { next(e); }
});
export default router;
EOF

# ---------- src/routes/upload.js ----------
cat > src/routes/upload.js << 'EOF'
import { Router } from 'express';
import multer from 'multer';
import path from 'node:path';
import fs from 'node:fs';
import { randomUUID } from 'node:crypto';
import { config } from '../config/index.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
fs.mkdirSync(config.uploadDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (_req, _f, cb) => cb(null, config.uploadDir),
  filename: (_req, f, cb) => cb(null, `${randomUUID()}${path.extname(f.originalname).toLowerCase().slice(0, 10)}`),
});
const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_req, f, cb) => {
    const ok = /^image\/(png|jpeg|webp|gif)$/.test(f.mimetype);
    cb(ok ? null : new Error('unsupported mime'), ok);
  },
});

router.post('/', requireAuth, upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'no file' });
  res.status(201).json({ url: `/uploads/${req.file.filename}` });
});
export default router;
EOF

# ---------- src/routes/admin.js ----------
cat > src/routes/admin.js << 'EOF'
import { Router } from 'express';
import { z } from 'zod';
import { query, tx } from '../db/pool.js';
import { requireAuth } from '../middleware/auth.js';
import { requireRole } from '../middleware/role.js';
import { validate } from '../middleware/validate.js';
import { HttpError } from '../middleware/errorHandler.js';
import { log } from '../utils/logger.js';

const router = Router();
router.use(requireAuth, requireRole('admin'));

const roleSchema = z.object({ role: z.enum(['user', 'moderator', 'admin', 'owner']) });

router.get('/stats', async (_req, res, next) => {
  try {
    const { rows } = await query(`
      SELECT
        (SELECT COUNT(*)::int FROM users)             AS users,
        (SELECT COUNT(*)::int FROM posts)             AS posts,
        (SELECT COUNT(*)::int FROM comments)          AS comments,
        (SELECT COUNT(*)::int FROM messages)          AS messages,
        (SELECT COUNT(*)::int FROM friendships WHERE status='accepted') AS friendships,
        (SELECT COUNT(*)::int FROM users WHERE created_at > now() - interval '24 hours') AS signups_24h
    `);
    res.json({ stats: rows[0] });
  } catch (e) { next(e); }
});

router.get('/users', async (req, res, next) => {
  try {
    const limit = Math.min(Number(req.query.limit) || 50, 200);
    const q = (req.query.q || '').toString();
    const { rows } = await query(
      `SELECT id, username, email, full_name, role, is_private, created_at, last_seen
         FROM users
        WHERE ($1 = '' OR username ILIKE '%'||$1||'%' OR email ILIKE '%'||$1||'%')
        ORDER BY created_at DESC LIMIT $2`,
      [q, limit]
    );
    res.json({ users: rows });
  } catch (e) { next(e); }
});

router.patch('/users/:id/role', requireRole('owner'), validate(roleSchema), async (req, res, next) => {
  try {
    if (req.params.id === req.user.id && req.body.role !== 'owner') {
      throw new HttpError(400, 'invalid', 'cannot demote yourself');
    }
    const { rows, rowCount } = await query(
      'UPDATE users SET role = $1 WHERE id = $2 RETURNING id, username, role',
      [req.body.role, req.params.id]
    );
    if (!rowCount) throw new HttpError(404, 'not_found', 'user not found');
    await query(
      `INSERT INTO audit_log (actor_id, action, target_id, meta, ip)
       VALUES ($1, 'role_change', $2, $3, $4)`,
      [req.user.id, req.params.id, JSON.stringify({ role: req.body.role }), req.ip]
    );
    log.info('role changed', { actor: req.user.username, target: rows[0].username, role: req.body.role });
    res.json({ user: rows[0] });
  } catch (e) { next(e); }
});

router.delete('/users/:id', requireRole('owner'), async (req, res, next) => {
  try {
    if (req.params.id === req.user.id) throw new HttpError(400, 'invalid', 'cannot delete yourself');
    await tx(async (client) => {
      await client.query('DELETE FROM users WHERE id = $1', [req.params.id]);
      await client.query(
        `INSERT INTO audit_log (actor_id, action, target_id, ip)
         VALUES ($1, 'user_delete', $2, $3)`,
        [req.user.id, req.params.id, req.ip]
      );
    });
    res.status(204).end();
  } catch (e) { next(e); }
});

router.delete('/posts/:id', async (req, res, next) => {
  try {
    await query('DELETE FROM posts WHERE id = $1', [req.params.id]);
    await query(
      `INSERT INTO audit_log (actor_id, action, target_id, ip)
       VALUES ($1, 'post_delete', $2, $3)`,
      [req.user.id, req.params.id, req.ip]
    );
    res.status(204).end();
  } catch (e) { next(e); }
});

router.get('/audit', requireRole('owner'), async (req, res, next) => {
  try {
    const limit = Math.min(Number(req.query.limit) || 100, 500);
    const { rows } = await query(
      `SELECT a.id, a.action, a.target_id, a.meta, a.ip, a.created_at,
              u.username AS actor_username
         FROM audit_log a LEFT JOIN users u ON u.id = a.actor_id
        ORDER BY a.created_at DESC LIMIT $1`,
      [limit]
    );
    res.json({ audit: rows });
  } catch (e) { next(e); }
});

router.get('/settings', requireRole('owner'), async (_req, res, next) => {
  try {
    const { rows } = await query('SELECT key, value, updated_at FROM site_settings ORDER BY key');
    res.json({ settings: rows });
  } catch (e) { next(e); }
});

const settingSchema = z.object({ key: z.string().min(1).max(64), value: z.any() });
router.put('/settings', requireRole('owner'), validate(settingSchema), async (req, res, next) => {
  try {
    const { rows } = await query(
      `INSERT INTO site_settings (key, value, updated_at)
       VALUES ($1, $2, now())
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()
       RETURNING key, value, updated_at`,
      [req.body.key, req.body.value]
    );
    await query(
      `INSERT INTO audit_log (actor_id, action, meta, ip)
       VALUES ($1, 'setting_update', $2, $3)`,
      [req.user.id, JSON.stringify({ key: req.body.key }), req.ip]
    );
    res.json({ setting: rows[0] });
  } catch (e) { next(e); }
});

export default router;
EOF

# ---------- src/sockets/index.js ----------
cat > src/sockets/index.js << 'EOF'
import { Server } from 'socket.io';
import { verifyToken } from '../utils/jwt.js';
import { config } from '../config/index.js';
import { log } from '../utils/logger.js';
import { sendMessage } from '../services/messageService.js';

export function attachSockets(httpServer) {
  const io = new Server(httpServer, {
    cors: { origin: config.corsOrigin, credentials: true },
    path: '/ws',
  });

  io.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error('unauthorized'));
    try {
      const p = verifyToken(token);
      socket.data.user = { id: p.sub, username: p.username };
      next();
    } catch {
      next(new Error('unauthorized'));
    }
  });

  io.on('connection', (socket) => {
    const uid = socket.data.user.id;
    socket.join(`user:${uid}`);
    log.info('socket connected', { uid });

    socket.on('conv:join', ({ conversationId }) => socket.join(`conv:${conversationId}`));

    socket.on('message:send', async ({ conversationId, body }, ack) => {
      try {
        const result = await sendMessage({ conversationId, senderId: uid, body });
        for (const peerId of result.peerIds) {
          io.to(`user:${peerId}`).emit('message:new', { conversationId, message: result.message });
        }
        ack?.({ ok: true, message: result.message });
      } catch (e) {
        ack?.({ ok: false, error: e.code || 'error' });
      }
    });

    socket.on('typing', ({ conversationId }) => {
      socket.to(`conv:${conversationId}`).emit('typing', { conversationId, userId: uid });
    });
  });

  return io;
}

export function emitToUser(io, userId, event, payload) {
  io.to(`user:${userId}`).emit(event, payload);
}
EOF

# ---------- src/index.js ----------
cat > src/index.js << 'EOF'
import express from 'express';
import http from 'node:http';
import cors from 'cors';
import helmet from 'helmet';
import path from 'node:path';
import { config } from './config/index.js';
import { log } from './utils/logger.js';
import { errorHandler } from './middleware/errorHandler.js';
import authRoutes from './routes/auth.js';
import userRoutes from './routes/users.js';
import postRoutes from './routes/posts.js';
import friendRoutes from './routes/friends.js';
import messageRoutes from './routes/messages.js';
import notificationRoutes from './routes/notifications.js';
import uploadRoutes from './routes/upload.js';
import adminRoutes from './routes/admin.js';
import { attachSockets } from './sockets/index.js';

const app = express();
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(cors({ origin: config.corsOrigin, credentials: true }));
app.use(express.json({ limit: '1mb' }));

app.get('/health', (_req, res) => res.json({ ok: true, ts: Date.now() }));
app.use('/uploads', express.static(path.resolve(config.uploadDir)));
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/posts', postRoutes);
app.use('/api/friends', friendRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/admin', adminRoutes);
app.use(errorHandler);

const server = http.createServer(app);
app.set('io', attachSockets(server));
server.listen(config.port, () => log.info(`woodnet server on :${config.port}`));
process.on('SIGTERM', () => server.close(() => process.exit(0)));
EOF

echo ""
echo "==================================================="
echo " BOOTSTRAP PART 3 COMPLETE"
echo " Routes + Sockets + index.js created"
echo "==================================================="
find src/routes src/sockets -type f | sort
ls -la src/index.js
echo ""
echo " Backend files total:"
find src -type f | wc -l
echo "==================================================="
