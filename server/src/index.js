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
app.use(express.static(path.resolve('public')));
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/posts', postRoutes);
app.use('/api/friends', friendRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/admin', adminRoutes);
// SPA fallback: كل مسار غير API/static يخدم index.html
app.get(/^(?!\/api|\/uploads|\/health).*/, (_req, res) => {
  res.sendFile(path.resolve('public/index.html'));
});
app.use(errorHandler);

const server = http.createServer(app);
app.set('io', attachSockets(server));
server.listen(config.port, '0.0.0.0', () => log.info(`woodnet server on :${config.port}`));
process.on('SIGTERM', () => server.close(() => process.exit(0)));
