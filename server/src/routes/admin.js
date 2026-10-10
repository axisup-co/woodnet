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
