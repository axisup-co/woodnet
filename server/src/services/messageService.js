import { query, tx } from '../db/pool.js';
import { HttpError } from '../middleware/errorHandler.js';

export async function getOrCreateConversation(userA, userB) {
  return tx(async (client) => {
    const ex = await client.query(
      `SELECT c.id FROM conversations c
        JOIN conversation_members m1 ON m1.conversation_id = c.id AND m1.user_id = $1
        JOIN conversation_members m2 ON m2.conversation_id = c.id AND m2.user_id = $2
       LIMIT 1`,
      [userA, userB]
    );
    if (ex.rowCount) return ex.rows[0].id;
    const { rows } = await client.query('INSERT INTO conversations DEFAULT VALUES RETURNING id');
    const id = rows[0].id;
    await client.query(
      'INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1,$2),($1,$3)',
      [id, userA, userB]
    );
    return id;
  });
}

export async function listConversations(userId) {
  const { rows } = await query(
    `SELECT c.id, c.last_message_at,
            (SELECT json_build_object('id', u.id, 'username', u.username, 'full_name', u.full_name, 'avatar_url', u.avatar_url)
               FROM conversation_members cm JOIN users u ON u.id = cm.user_id
              WHERE cm.conversation_id = c.id AND cm.user_id <> $1 LIMIT 1) AS peer,
            (SELECT body FROM messages m WHERE m.conversation_id = c.id ORDER BY m.created_at DESC LIMIT 1) AS last_message
       FROM conversations c
       JOIN conversation_members me ON me.conversation_id = c.id AND me.user_id = $1
      ORDER BY c.last_message_at DESC LIMIT 100`,
    [userId]
  );
  return rows;
}

export async function listMessages({ conversationId, userId, limit = 50, before }) {
  const member = await query('SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2', [conversationId, userId]);
  if (!member.rowCount) throw new HttpError(403, 'forbidden', 'not a member');
  const params = [conversationId, limit];
  let clause = '';
  if (before) { clause = 'AND created_at < $3'; params.push(before); }
  const { rows } = await query(
    `SELECT id, sender_id, body, created_at, read_at FROM messages
      WHERE conversation_id = $1 ${clause}
      ORDER BY created_at DESC LIMIT $2`,
    params
  );
  return rows.reverse();
}

export async function sendMessage({ conversationId, senderId, body }) {
  return tx(async (client) => {
    const m = await client.query('SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2', [conversationId, senderId]);
    if (!m.rowCount) throw new HttpError(403, 'forbidden', 'not a member');
    const { rows } = await client.query(
      `INSERT INTO messages (conversation_id, sender_id, body)
       VALUES ($1,$2,$3) RETURNING id, sender_id, body, created_at`,
      [conversationId, senderId, body]
    );
    await client.query('UPDATE conversations SET last_message_at = now() WHERE id = $1', [conversationId]);
    const peers = await client.query(
      'SELECT user_id FROM conversation_members WHERE conversation_id = $1 AND user_id <> $2',
      [conversationId, senderId]
    );
    return { message: rows[0], peerIds: peers.rows.map((r) => r.user_id) };
  });
}
