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
