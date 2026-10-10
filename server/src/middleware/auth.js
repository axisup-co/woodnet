import { verifyToken } from '../utils/jwt.js';
import { HttpError } from './errorHandler.js';

function parse(req) {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') ? h.slice(7) : null;
}

export function requireAuth(req, _res, next) {
  const token = parse(req);
  if (!token) return next(new HttpError(401, 'unauthorized', 'missing token'));
  try {
    const p = verifyToken(token);
    req.user = { id: p.sub, username: p.username };
    next();
  } catch {
    next(new HttpError(401, 'unauthorized', 'invalid token'));
  }
}

export function optionalAuth(req, _res, next) {
  const token = parse(req);
  if (token) {
    try {
      const p = verifyToken(token);
      req.user = { id: p.sub, username: p.username };
    } catch { /* ignore */ }
  }
  next();
}
