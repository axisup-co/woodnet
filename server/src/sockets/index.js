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
