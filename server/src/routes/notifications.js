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
