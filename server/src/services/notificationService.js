import { query } from '../db/pool.js';

export async function createNotification({ userId, type, actorId, entityId, payload }) {
  if (userId === actorId && type !== 'system') return null;
  const { rows } = await query(
    `INSERT INTO notifications (user_id, type, actor_id, entity_id, payload)
     VALUES ($1,$2,$3,$4,$5) RETURNING *`,
    [userId, type, actorId || null, entityId || null, payload || null]
  );
  return rows[0];
}

export async function listNotifications(userId, limit = 50) {
  const { rows } = await query(
    `SELECT n.*, u.username AS actor_username, u.avatar_url AS actor_avatar
       FROM notifications n LEFT JOIN users u ON u.id = n.actor_id
      WHERE n.user_id = $1 ORDER BY n.created_at DESC LIMIT $2`,
    [userId, limit]
  );
  return rows;
}

export async function markRead(userId, notificationId) {
  await query('UPDATE notifications SET read_at = now() WHERE id = $1 AND user_id = $2', [notificationId, userId]);
}
