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
