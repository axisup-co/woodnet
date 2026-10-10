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
