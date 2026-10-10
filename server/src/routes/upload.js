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
