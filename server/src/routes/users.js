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
