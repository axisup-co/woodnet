import { query, tx } from '../db/pool.js';
import { HttpError } from '../middleware/errorHandler.js';

export async function createPost({ authorId, content, mediaUrl, visibility = 'public' }) {
  if (!content && !mediaUrl) throw new HttpError(400, 'validation_error', 'post is empty');
  const { rows } = await query(
    `INSERT INTO posts (author_id, content, media_url, visibility)
     VALUES ($1, $2, $3, $4) RETURNING *`,
    [authorId, content || null, mediaUrl || null, visibility]
  );
  return rows[0];
}

export async function deletePost({ postId, userId }) {
  const { rowCount } = await query('DELETE FROM posts WHERE id = $1 AND author_id = $2', [postId, userId]);
  if (!rowCount) throw new HttpError(404, 'not_found', 'post not found');
}

export async function getFeed({ userId, limit = 20, cursor }) {
  const params = [userId, limit];
  let clause = '';
  if (cursor) { clause = 'AND p.created_at < $3'; params.push(cursor); }
  const { rows } = await query(
    `SELECT p.id, p.author_id, p.content, p.media_url, p.visibility, p.created_at,
            u.username AS author_username, u.full_name AS author_full_name, u.avatar_url AS author_avatar,
            (SELECT COUNT(*)::int FROM likes l WHERE l.post_id = p.id) AS like_count,
            (SELECT COUNT(*)::int FROM comments c WHERE c.post_id = p.id) AS comment_count,
            EXISTS (SELECT 1 FROM likes l WHERE l.post_id = p.id AND l.user_id = $1) AS liked_by_me
       FROM posts p JOIN users u ON u.id = p.author_id
      WHERE (p.visibility = 'public' OR p.author_id = $1
             OR p.author_id IN (
               SELECT CASE WHEN requester_id = $1 THEN addressee_id ELSE requester_id END
                 FROM friendships
                WHERE status = 'accepted' AND (requester_id = $1 OR addressee_id = $1)))
        ${clause}
      ORDER BY p.created_at DESC LIMIT $2`,
    params
  );
  const nextCursor = rows.length === limit ? rows[rows.length - 1].created_at : null;
  return { items: rows, nextCursor };
}

export async function likePost({ postId, userId }) {
  return tx(async (client) => {
    const p = await client.query('SELECT author_id FROM posts WHERE id = $1', [postId]);
    if (!p.rowCount) throw new HttpError(404, 'not_found', 'post not found');
    await client.query('INSERT INTO likes (user_id, post_id) VALUES ($1,$2) ON CONFLICT DO NOTHING', [userId, postId]);
    return { postAuthorId: p.rows[0].author_id };
  });
}

export async function unlikePost({ postId, userId }) {
  await query('DELETE FROM likes WHERE user_id = $1 AND post_id = $2', [userId, postId]);
}

export async function listComments({ postId }) {
  const { rows } = await query(
    `SELECT c.id, c.content, c.created_at, u.id AS author_id, u.username, u.full_name, u.avatar_url
       FROM comments c JOIN users u ON u.id = c.author_id
      WHERE c.post_id = $1 ORDER BY c.created_at ASC LIMIT 200`,
    [postId]
  );
  return rows;
}

export async function addComment({ postId, authorId, content }) {
  const { rows } = await query(
    `INSERT INTO comments (post_id, author_id, content) VALUES ($1,$2,$3)
     RETURNING id, content, created_at,
       (SELECT username FROM users WHERE id = $2) AS username,
       (SELECT avatar_url FROM users WHERE id = $2) AS avatar_url`,
    [postId, authorId, content]
  );
  const owner = await query('SELECT author_id FROM posts WHERE id = $1', [postId]);
  return { comment: rows[0], postAuthorId: owner.rows[0]?.author_id };
}
