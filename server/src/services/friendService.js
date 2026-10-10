import { query, tx } from '../db/pool.js';
import { HttpError } from '../middleware/errorHandler.js';

export async function sendRequest({ requesterId, addresseeId }) {
  if (requesterId === addresseeId) throw new HttpError(400, 'validation_error', 'cannot friend yourself');
  return tx(async (client) => {
    const ex = await client.query(
      `SELECT id, status, requester_id FROM friendships
        WHERE (requester_id = $1 AND addressee_id = $2)
           OR (requester_id = $2 AND addressee_id = $1)`,
      [requesterId, addresseeId]
    );
    if (ex.rowCount) {
      const row = ex.rows[0];
      if (row.status === 'accepted') throw new HttpError(409, 'conflict', 'already friends');
      if (row.requester_id === addresseeId) {
        await client.query(`UPDATE friendships SET status='accepted', updated_at=now() WHERE id=$1`, [row.id]);
        return { status: 'accepted' };
      }
      throw new HttpError(409, 'conflict', 'request already pending');
    }
    await client.query(
      `INSERT INTO friendships (requester_id, addressee_id, status) VALUES ($1,$2,'pending')`,
      [requesterId, addresseeId]
    );
    return { status: 'pending' };
  });
}

export async function respondRequest({ userId, requestId, accept }) {
  const { rows, rowCount } = await query(
    `UPDATE friendships SET status = $3, updated_at = now()
      WHERE id = $1 AND addressee_id = $2 AND status = 'pending'
      RETURNING requester_id, addressee_id`,
    [requestId, userId, accept ? 'accepted' : 'rejected']
  );
  if (!rowCount) throw new HttpError(404, 'not_found', 'request not found');
  return rows[0];
}

export async function listFriends(userId) {
  const { rows } = await query(
    `SELECT u.id, u.username, u.full_name, u.avatar_url
       FROM friendships f
       JOIN users u ON u.id = CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END
      WHERE f.status = 'accepted' AND (f.requester_id = $1 OR f.addressee_id = $1)
      ORDER BY u.username`,
    [userId]
  );
  return rows;
}

export async function listRequests(userId) {
  const { rows } = await query(
    `SELECT f.id, f.created_at, u.id AS requester_id, u.username, u.full_name, u.avatar_url
       FROM friendships f JOIN users u ON u.id = f.requester_id
      WHERE f.addressee_id = $1 AND f.status = 'pending'
      ORDER BY f.created_at DESC`,
    [userId]
  );
  return rows;
}
