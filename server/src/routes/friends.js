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
