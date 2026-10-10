import { query } from '../db/pool.js';
import { HttpError } from './errorHandler.js';

const RANK = { user: 0, moderator: 1, admin: 2, owner: 3 };

export function requireRole(min) {
  return async (req, _res, next) => {
    try {
      const { rows } = await query('SELECT role FROM users WHERE id = $1', [req.user.id]);
      if (!rows.length) throw new HttpError(401, 'unauthorized', 'user not found');
      const current = rows[0].role || 'user';
      if ((RANK[current] ?? 0) < (RANK[min] ?? 99)) {
        throw new HttpError(403, 'forbidden', `requires ${min}`);
      }
      req.role = current;
      next();
    } catch (e) { next(e); }
  };
}
