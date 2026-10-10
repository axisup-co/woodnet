#!/data/data/com.termux/files/usr/bin/bash
set -e
mkdir -p ~/woodnet/client/src/{api,context,components,pages}
cd ~/woodnet/client

cat > package.json << 'EOF'
{
  "name": "woodnet-client",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0",
    "build": "vite build",
    "preview": "vite preview --host 0.0.0.0"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-router-dom": "^6.26.0",
    "socket.io-client": "^4.7.5"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.3.1",
    "vite": "^5.4.0"
  }
}
EOF

cat > vite.config.js << 'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    host: '0.0.0.0',
    proxy: {
      '/api': 'http://localhost:4000',
      '/uploads': 'http://localhost:4000',
      '/ws': { target: 'http://localhost:4000', ws: true },
    },
  },
});
EOF

cat > index.html << 'EOF'
<!doctype html>
<html lang="ar" dir="rtl">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>WoodNet</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
EOF

cat > src/main.jsx << 'EOF'
import React from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App.jsx';
import { AuthProvider } from './context/AuthContext.jsx';
import { SocketProvider } from './context/SocketContext.jsx';
import './styles.css';

createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <SocketProvider>
          <App />
        </SocketProvider>
      </AuthProvider>
    </BrowserRouter>
  </React.StrictMode>
);
EOF

cat > src/api/client.js << 'EOF'
const BASE = '/api';
const getToken = () => localStorage.getItem('token');

export async function api(path, { method = 'GET', body, headers = {} } = {}) {
  const token = getToken();
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(data.message || res.statusText), { status: res.status, code: data.error });
  return data;
}

export async function uploadFile(file) {
  const fd = new FormData();
  fd.append('file', file);
  const token = getToken();
  const res = await fetch(`${BASE}/upload`, {
    method: 'POST',
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: fd,
  });
  if (!res.ok) throw new Error('upload failed');
  return (await res.json()).url;
}
EOF

cat > src/context/AuthContext.jsx << 'EOF'
import { createContext, useContext, useEffect, useState } from 'react';
import { api } from '../api/client.js';

const Ctx = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const token = localStorage.getItem('token');
    if (!token) { setLoading(false); return; }
    api('/auth/me').then((d) => setUser(d.user))
      .catch(() => localStorage.removeItem('token'))
      .finally(() => setLoading(false));
  }, []);

  async function login(email, password) {
    const { user, token } = await api('/auth/login', { method: 'POST', body: { email, password } });
    localStorage.setItem('token', token); setUser(user); return user;
  }
  async function register(payload) {
    const { user, token } = await api('/auth/register', { method: 'POST', body: payload });
    localStorage.setItem('token', token); setUser(user); return user;
  }
  function logout() { localStorage.removeItem('token'); setUser(null); }

  return <Ctx.Provider value={{ user, setUser, loading, login, register, logout }}>{children}</Ctx.Provider>;
}
export const useAuth = () => useContext(Ctx);
EOF

cat > src/context/SocketContext.jsx << 'EOF'
import { createContext, useContext, useEffect, useState } from 'react';
import { io } from 'socket.io-client';
import { useAuth } from './AuthContext.jsx';

const Ctx = createContext(null);

export function SocketProvider({ children }) {
  const { user } = useAuth();
  const [socket, setSocket] = useState(null);
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    if (!user) {
      setSocket((s) => { s?.disconnect(); return null; });
      setConnected(false);
      return;
    }
    const token = localStorage.getItem('token');
    const s = io(window.location.origin, { path: '/ws', auth: { token }, transports: ['websocket'] });
    s.on('connect', () => setConnected(true));
    s.on('disconnect', () => setConnected(false));
    setSocket(s);
    return () => { s.disconnect(); };
  }, [user]);

  return <Ctx.Provider value={{ socket, connected }}>{children}</Ctx.Provider>;
}
export const useSocket = () => useContext(Ctx);
EOF

cat > src/App.jsx << 'EOF'
import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuth } from './context/AuthContext.jsx';
import Navbar from './components/Navbar.jsx';
import Login from './pages/Login.jsx';
import Register from './pages/Register.jsx';
import Feed from './pages/Feed.jsx';
import Profile from './pages/Profile.jsx';
import Friends from './pages/Friends.jsx';
import Messages from './pages/Messages.jsx';
import Notifications from './pages/Notifications.jsx';
import Admin from './pages/Admin.jsx';

function Protected({ children }) {
  const { user, loading } = useAuth();
  if (loading) return <div className="center muted">...</div>;
  if (!user) return <Navigate to="/login" replace />;
  return children;
}

export default function App() {
  return (
    <div className="app">
      <Navbar />
      <main className="main">
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/register" element={<Register />} />
          <Route path="/" element={<Protected><Feed /></Protected>} />
          <Route path="/u/:username" element={<Protected><Profile /></Protected>} />
          <Route path="/friends" element={<Protected><Friends /></Protected>} />
          <Route path="/messages" element={<Protected><Messages /></Protected>} />
          <Route path="/messages/:conversationId" element={<Protected><Messages /></Protected>} />
          <Route path="/notifications" element={<Protected><Notifications /></Protected>} />
          <Route path="/admin" element={<Protected><Admin /></Protected>} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
    </div>
  );
}
EOF

cat > src/components/Navbar.jsx << 'EOF'
import { Link, NavLink, useNavigate } from 'react-router-dom';
import { useState } from 'react';
import { useAuth } from '../context/AuthContext.jsx';
import { api } from '../api/client.js';

export default function Navbar() {
  const { user, logout } = useAuth();
  const nav = useNavigate();
  const [q, setQ] = useState('');
  const [results, setResults] = useState([]);

  async function search(e) {
    e.preventDefault();
    if (!q.trim()) return setResults([]);
    try { setResults((await api(`/users/search?q=${encodeURIComponent(q)}`)).users); } catch {}
  }
  function go(u) { setResults([]); setQ(''); nav(`/u/${u}`); }

  return (
    <header className="nav">
      <Link to="/" className="brand">WoodNet</Link>
      {user && (
        <>
          <form className="search" onSubmit={search}>
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="بحث..." />
            {results.length > 0 && (
              <div className="search-drop">
                {results.map((u) => (
                  <div key={u.id} className="search-item" onClick={() => go(u.username)}>
                    <span>{u.full_name || u.username}</span>
                    <span className="muted"> @{u.username}</span>
                  </div>
                ))}
              </div>
            )}
          </form>
          <nav className="nav-links">
            <NavLink to="/">الرئيسية</NavLink>
            <NavLink to="/friends">الأصدقاء</NavLink>
            <NavLink to="/messages">الرسائل</NavLink>
            <NavLink to="/notifications">الإشعارات</NavLink>
            <Link to={`/u/${user.username}`} className="pill">{user.username}</Link>
            <button className="btn-ghost" onClick={() => { logout(); nav('/login'); }}>خروج</button>
          </nav>
        </>
      )}
    </header>
  );
}
EOF

cat > src/components/PostComposer.jsx << 'EOF'
import { useState } from 'react';
import { api, uploadFile } from '../api/client.js';

export default function PostComposer({ onCreated }) {
  const [content, setContent] = useState('');
  const [mediaUrl, setMediaUrl] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [busy, setBusy] = useState(false);

  async function pick(e) {
    const f = e.target.files?.[0];
    if (!f) return;
    setUploading(true);
    try { setMediaUrl(await uploadFile(f)); } finally { setUploading(false); }
  }
  async function submit() {
    if (!content.trim() && !mediaUrl) return;
    setBusy(true);
    try {
      const { post } = await api('/posts', { method: 'POST', body: { content: content.trim(), mediaUrl } });
      setContent(''); setMediaUrl(null);
      onCreated?.(post);
    } finally { setBusy(false); }
  }

  return (
    <div className="card composer">
      <textarea value={content} onChange={(e) => setContent(e.target.value)} placeholder="بماذا تفكر؟" rows={3} />
      {mediaUrl && <img className="preview" src={mediaUrl} alt="" />}
      <div className="composer-row">
        <label className="btn-ghost">صورة<input type="file" accept="image/*" hidden onChange={pick} /></label>
        {uploading && <span className="muted">...</span>}
        <button className="btn" disabled={busy || uploading} onClick={submit}>نشر</button>
      </div>
    </div>
  );
}
EOF

cat > src/components/PostCard.jsx << 'EOF'
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api/client.js';

export default function PostCard({ post, onDelete }) {
  const [liked, setLiked] = useState(!!post.liked_by_me);
  const [likeCount, setLikeCount] = useState(post.like_count ?? 0);
  const [showComments, setShowComments] = useState(false);
  const [comments, setComments] = useState([]);
  const [text, setText] = useState('');
  const [commentCount, setCommentCount] = useState(post.comment_count ?? 0);

  async function toggleLike() {
    if (liked) {
      await api(`/posts/${post.id}/like`, { method: 'DELETE' });
      setLiked(false); setLikeCount((c) => Math.max(0, c - 1));
    } else {
      await api(`/posts/${post.id}/like`, { method: 'POST' });
      setLiked(true); setLikeCount((c) => c + 1);
    }
  }

  useEffect(() => {
    if (showComments) api(`/posts/${post.id}/comments`).then((d) => setComments(d.comments));
  }, [showComments, post.id]);

  async function addComment(e) {
    e.preventDefault();
    if (!text.trim()) return;
    const { comment } = await api(`/posts/${post.id}/comments`, { method: 'POST', body: { content: text.trim() } });
    setComments((c) => [...c, comment]);
    setText(''); setCommentCount((c) => c + 1);
  }

  const author = post.author_username || post.username;
  return (
    <article className="card post">
      <header className="post-head">
        <Link to={`/u/${author}`} className="post-author">
          {post.author_avatar || post.avatar_url
            ? <img className="avatar" src={post.author_avatar || post.avatar_url} alt="" />
            : <div className="avatar placeholder" />}
          <div>
            <div className="name">{post.author_full_name || post.full_name || author}</div>
            <div className="muted small">@{author} · {new Date(post.created_at).toLocaleString('ar')}</div>
          </div>
        </Link>
        {onDelete && <button className="btn-ghost" onClick={() => onDelete(post.id)}>حذف</button>}
      </header>
      {post.content && <p className="post-body">{post.content}</p>}
      {post.media_url && <img className="post-media" src={post.media_url} alt="" />}
      <footer className="post-actions">
        <button className={liked ? 'btn-ghost active' : 'btn-ghost'} onClick={toggleLike}>❤ {likeCount}</button>
        <button className="btn-ghost" onClick={() => setShowComments((v) => !v)}>💬 {commentCount}</button>
      </footer>
      {showComments && (
        <div className="comments">
          {comments.map((c) => (
            <div key={c.id} className="comment">
              <Link to={`/u/${c.username}`} className="muted small">@{c.username} </Link>
              <span>{c.content}</span>
            </div>
          ))}
          <form onSubmit={addComment} className="comment-form">
            <input value={text} onChange={(e) => setText(e.target.value)} placeholder="اكتب تعليقاً..." />
            <button className="btn">إرسال</button>
          </form>
        </div>
      )}
    </article>
  );
}
EOF

cat > src/pages/Login.jsx << 'EOF'
import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext.jsx';

export default function Login() {
  const { login } = useAuth();
  const nav = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [err, setErr] = useState(null);

  async function submit(e) {
    e.preventDefault(); setErr(null);
    try { await login(email, password); nav('/'); } catch (e) { setErr(e.message); }
  }

  return (
    <div className="auth-page">
      <form className="card auth-card" onSubmit={submit}>
        <h1>WoodNet</h1>
        <p className="muted">تسجيل الدخول</p>
        {err && <div className="error">{err}</div>}
        <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="البريد" required />
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="كلمة المرور" required />
        <button className="btn">دخول</button>
        <p className="muted">ليس لديك حساب؟ <Link to="/register">سجل الآن</Link></p>
      </form>
    </div>
  );
}
EOF

cat > src/pages/Register.jsx << 'EOF'
import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext.jsx';

export default function Register() {
  const { register } = useAuth();
  const nav = useNavigate();
  const [form, setForm] = useState({ username: '', email: '', password: '', fullName: '' });
  const [err, setErr] = useState(null);

  async function submit(e) {
    e.preventDefault(); setErr(null);
    try { await register(form); nav('/'); } catch (e) { setErr(e.message); }
  }

  return (
    <div className="auth-page">
      <form className="card auth-card" onSubmit={submit}>
        <h1>إنشاء حساب</h1>
        {err && <div className="error">{err}</div>}
        <input value={form.username} onChange={(e) => setForm({ ...form, username: e.target.value })} placeholder="اسم المستخدم" required minLength={3} />
        <input value={form.fullName} onChange={(e) => setForm({ ...form, fullName: e.target.value })} placeholder="الاسم الكامل" />
        <input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="البريد" required />
        <input type="password" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} placeholder="كلمة المرور (8+)" required minLength={8} />
        <button className="btn">تسجيل</button>
        <p className="muted">لديك حساب؟ <Link to="/login">ادخل</Link></p>
      </form>
    </div>
  );
}
EOF

cat > src/pages/Feed.jsx << 'EOF'
import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../api/client.js';
import PostComposer from '../components/PostComposer.jsx';
import PostCard from '../components/PostCard.jsx';
import { useAuth } from '../context/AuthContext.jsx';

export default function Feed() {
  const { user } = useAuth();
  const [posts, setPosts] = useState([]);
  const [cursor, setCursor] = useState(null);
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);
  const sentinel = useRef(null);

  const load = useCallback(async (reset) => {
    if (loading || (done && !reset)) return;
    setLoading(true);
    try {
      const qs = new URLSearchParams({ limit: '20' });
      if (!reset && cursor) qs.set('cursor', cursor);
      const data = await api(`/posts/feed?${qs}`);
      setPosts((prev) => reset ? data.items : [...prev, ...data.items]);
      setCursor(data.nextCursor);
      if (!data.nextCursor) setDone(true);
    } finally { setLoading(false); }
  }, [cursor, done, loading]);

  useEffect(() => { load(true); }, []);
  useEffect(() => {
    const el = sentinel.current; if (!el) return;
    const io = new IntersectionObserver((es) => { if (es[0].isIntersecting) load(false); });
    io.observe(el);
    return () => io.disconnect();
  }, [load]);

  function onCreated(post) {
    const enriched = { ...post, author_username: user.username, author_full_name: user.full_name, author_avatar: user.avatar_url, like_count: 0, comment_count: 0 };
    setPosts((p) => [enriched, ...p]);
  }
  async function del(id) {
    if (!confirm('حذف المنشور؟')) return;
    await api(`/posts/${id}`, { method: 'DELETE' });
    setPosts((p) => p.filter((x) => x.id !== id));
  }

  return (
    <div className="feed">
      <PostComposer onCreated={onCreated} />
      {posts.map((p) => (
        <PostCard key={p.id} post={p} onDelete={(p.author_username === user.username || p.author_id === user.id) ? del : undefined} />
      ))}
      <div ref={sentinel} className="sentinel" />
      {loading && <div className="muted center">...</div>}
    </div>
  );
}
EOF

cat > src/pages/Profile.jsx << 'EOF'
import { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { api } from '../api/client.js';
import { useAuth } from '../context/AuthContext.jsx';
import PostCard from '../components/PostCard.jsx';

export default function Profile() {
  const { username } = useParams();
  const nav = useNavigate();
  const { user: me } = useAuth();
  const [data, setData] = useState(null);
  const [err, setErr] = useState(null);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState({ fullName: '', bio: '' });

  useEffect(() => {
    api(`/users/${username}`).then((d) => {
      setData(d);
      setForm({ fullName: d.user.full_name || '', bio: d.user.bio || '' });
    }).catch((e) => setErr(e.message));
  }, [username]);

  if (err) return <div className="center error">{err}</div>;
  if (!data) return <div className="center muted">...</div>;

  const { user, posts, stats } = data;
  const isMe = me?.username === user.username;

  async function save() {
    const { user: u } = await api('/users/me', { method: 'PATCH', body: { fullName: form.fullName, bio: form.bio } });
    setData((d) => ({ ...d, user: { ...d.user, ...u } }));
    setEditing(false);
  }
  async function addFriend() {
    try {
      const r = await api('/friends/request', { method: 'POST', body: { addresseeId: user.id } });
      alert(r.status === 'accepted' ? 'تمت الصداقة' : 'تم إرسال الطلب');
    } catch (e) { alert(e.message); }
  }
  async function openChat() {
    const { conversationId } = await api('/messages/conversation', { method: 'POST', body: { peerId: user.id } });
    nav(`/messages/${conversationId}`);
  }

  return (
    <div className="profile">
      <div className="card profile-head">
        {user.cover_url ? <img className="cover" src={user.cover_url} alt="" /> : <div className="cover placeholder" />}
        <div className="profile-info">
          {user.avatar_url ? <img className="avatar lg" src={user.avatar_url} alt="" /> : <div className="avatar lg placeholder" />}
          <div>
            <h2>{user.full_name || user.username}</h2>
            <div className="muted">@{user.username}</div>
            {user.bio && <p>{user.bio}</p>}
            <div className="muted small">{stats.friend_count} صديق · {stats.post_count} منشور</div>
          </div>
          <div className="profile-actions">
            {isMe
              ? <button className="btn-ghost" onClick={() => setEditing((v) => !v)}>{editing ? 'إلغاء' : 'تعديل'}</button>
              : <>
                  <button className="btn" onClick={addFriend}>إضافة صديق</button>
                  <button className="btn-ghost" onClick={openChat}>رسالة</button>
                </>}
          </div>
        </div>
        {editing && (
          <div className="edit-form">
            <input value={form.fullName} onChange={(e) => setForm({ ...form, fullName: e.target.value })} placeholder="الاسم الكامل" />
            <textarea value={form.bio} onChange={(e) => setForm({ ...form, bio: e.target.value })} placeholder="نبذة" rows={3} />
            <button className="btn" onClick={save}>حفظ</button>
          </div>
        )}
      </div>
      <div className="feed">
        {posts.map((p) => (
          <PostCard key={p.id} post={{ ...p, author_username: user.username, author_full_name: user.full_name, author_avatar: user.avatar_url }} />
        ))}
      </div>
    </div>
  );
}
EOF

cat > src/pages/Friends.jsx << 'EOF'
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api/client.js';

export default function Friends() {
  const [friends, setFriends] = useState([]);
  const [requests, setRequests] = useState([]);

  async function refresh() {
    const [f, r] = await Promise.all([api('/friends'), api('/friends/requests')]);
    setFriends(f.friends); setRequests(r.requests);
  }
  useEffect(() => { refresh(); }, []);

  async function respond(requestId, accept) {
    await api('/friends/respond', { method: 'POST', body: { requestId, accept } });
    refresh();
  }

  return (
    <div className="friends">
      <section className="card">
        <h3>طلبات الصداقة</h3>
        {requests.length === 0 && <p className="muted">لا طلبات جديدة</p>}
        {requests.map((r) => (
          <div key={r.id} className="user-row">
            <Link to={`/u/${r.username}`}>@{r.username}</Link>
            <div>
              <button className="btn" onClick={() => respond(r.id, true)}>قبول</button>
              <button className="btn-ghost" onClick={() => respond(r.id, false)}>رفض</button>
            </div>
          </div>
        ))}
      </section>
      <section className="card">
        <h3>أصدقائي ({friends.length})</h3>
        {friends.map((f) => (
          <div key={f.id} className="user-row">
            <Link to={`/u/${f.username}`}>@{f.username}</Link>
            <span className="muted">{f.full_name}</span>
          </div>
        ))}
      </section>
    </div>
  );
}
EOF

cat > src/pages/Messages.jsx << 'EOF'
import { useEffect, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api } from '../api/client.js';
import { useAuth } from '../context/AuthContext.jsx';
import { useSocket } from '../context/SocketContext.jsx';

export default function Messages() {
  const { conversationId } = useParams();
  const nav = useNavigate();
  const { user } = useAuth();
  const { socket } = useSocket();
  const [convs, setConvs] = useState([]);
  const [messages, setMessages] = useState([]);
  const [body, setBody] = useState('');
  const bottomRef = useRef(null);

  async function loadConvs() { setConvs((await api('/messages/conversations')).conversations); }
  useEffect(() => { loadConvs(); }, []);

  useEffect(() => {
    if (!conversationId) { setMessages([]); return; }
    api(`/messages/conversations/${conversationId}/messages`).then((d) => setMessages(d.messages));
    socket?.emit('conv:join', { conversationId });
  }, [conversationId, socket]);

  useEffect(() => {
    if (!socket) return;
    function onNew({ conversationId: cid, message }) {
      if (cid === conversationId) setMessages((m) => [...m, message]);
      loadConvs();
    }
    socket.on('message:new', onNew);
    return () => socket.off('message:new', onNew);
  }, [socket, conversationId]);

  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [messages]);

  async function send(e) {
    e.preventDefault();
    if (!body.trim() || !conversationId) return;
    const text = body.trim(); setBody('');
    await api(`/messages/conversations/${conversationId}/messages`, { method: 'POST', body: { body: text } });
  }

  return (
    <div className="messages">
      <aside className="card conv-list">
        <h3>المحادثات</h3>
        {convs.map((c) => (
          <div key={c.id} className={c.id === conversationId ? 'conv active' : 'conv'} onClick={() => nav(`/messages/${c.id}`)}>
            <div className="name">{c.peer?.full_name || c.peer?.username || '—'}</div>
            <div className="muted small truncate">{c.last_message || ''}</div>
          </div>
        ))}
      </aside>
      <section className="card chat">
        {conversationId ? (
          <>
            <div className="chat-body">
              {messages.map((m) => (
                <div key={m.id} className={m.sender_id === user.id ? 'msg mine' : 'msg'}>
                  <span>{m.body}</span>
                  <span className="time muted small">{new Date(m.created_at).toLocaleTimeString('ar')}</span>
                </div>
              ))}
              <div ref={bottomRef} />
            </div>
            <form onSubmit={send} className="chat-form">
              <input value={body} onChange={(e) => setBody(e.target.value)} placeholder="اكتب..." />
              <button className="btn">إرسال</button>
            </form>
          </>
        ) : <div className="muted center">اختر محادثة</div>}
      </section>
    </div>
  );
}
EOF

cat > src/pages/Notifications.jsx << 'EOF'
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api/client.js';
import { useSocket } from '../context/SocketContext.jsx';

const labels = {
  like: 'أعجب بمنشورك',
  comment: 'علّق على منشورك',
  friend_request: 'أرسل طلب صداقة',
  friend_accept: 'قبل صداقتك',
};

export default function Notifications() {
  const { socket } = useSocket();
  const [items, setItems] = useState([]);

  useEffect(() => { api('/notifications').then((d) => setItems(d.notifications)); }, []);
  useEffect(() => {
    if (!socket) return;
    const on = (n) => setItems((prev) => [n, ...prev]);
    socket.on('notification:new', on);
    return () => socket.off('notification:new', on);
  }, [socket]);

  async function markRead(id) {
    await api(`/notifications/${id}/read`, { method: 'POST' });
    setItems((prev) => prev.map((n) => n.id === id ? { ...n, read_at: new Date().toISOString() } : n));
  }

  return (
    <div className="card notif-page">
      <h3>الإشعارات</h3>
      {items.length === 0 && <p className="muted">لا إشعارات</p>}
      {items.map((n) => (
        <div key={n.id} className={n.read_at ? 'notif' : 'notif unread'} onClick={() => markRead(n.id)}>
          {n.actor_username && <Link to={`/u/${n.actor_username}`}>@{n.actor_username}</Link>}
          <span> {labels[n.type] || n.type}</span>
          <span className="muted small"> · {new Date(n.created_at).toLocaleString('ar')}</span>
        </div>
      ))}
    </div>
  );
}
EOF

cat > src/pages/Admin.jsx << 'EOF'
import { useEffect, useState } from 'react';
import { api } from '../api/client.js';

export default function Admin() {
  const [tab, setTab] = useState('stats');
  const [stats, setStats] = useState(null);
  const [users, setUsers] = useState([]);
  const [q, setQ] = useState('');
  const [audit, setAudit] = useState([]);
  const [err, setErr] = useState(null);

  useEffect(() => {
    if (tab === 'stats') api('/admin/stats').then((d) => setStats(d.stats)).catch((e) => setErr(e.message));
    if (tab === 'users') api(`/admin/users?q=${encodeURIComponent(q)}`).then((d) => setUsers(d.users)).catch((e) => setErr(e.message));
    if (tab === 'audit') api('/admin/audit').then((d) => setAudit(d.audit)).catch((e) => setErr(e.message));
  }, [tab, q]);

  async function changeRole(id, role) {
    try {
      await api(`/admin/users/${id}/role`, { method: 'PATCH', body: { role } });
      setUsers((u) => u.map((x) => x.id === id ? { ...x, role } : x));
    } catch (e) { alert(e.message); }
  }

  return (
    <div className="card">
      <h2>لوحة التحكم</h2>
      <div className="tabs">
        {['stats', 'users', 'audit'].map((t) => (
          <button key={t} className={tab === t ? 'btn' : 'btn-ghost'} onClick={() => setTab(t)}>
            {t === 'stats' ? 'إحصائيات' : t === 'users' ? 'مستخدمون' : 'سجل التدقيق'}
          </button>
        ))}
      </div>
      {err && <div className="error">{err}</div>}
      {tab === 'stats' && stats && (
        <div className="stats-grid">
          {Object.entries(stats).map(([k, v]) => (
            <div key={k} className="stat"><div className="muted small">{k}</div><div className="big">{v}</div></div>
          ))}
        </div>
      )}
      {tab === 'users' && (
        <>
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="بحث بالاسم أو البريد" />
          {users.map((u) => (
            <div key={u.id} className="user-row">
              <span>@{u.username} <span className="muted">{u.email}</span></span>
              <select value={u.role} onChange={(e) => changeRole(u.id, e.target.value)}>
                {['user', 'moderator', 'admin', 'owner'].map((r) => <option key={r} value={r}>{r}</option>)}
              </select>
            </div>
          ))}
        </>
      )}
      {tab === 'audit' && (
        <div className="audit">
          {audit.map((a) => (
            <div key={a.id} className="audit-row">
              <span className="muted small">{new Date(a.created_at).toLocaleString('ar')}</span>
              <span> · {a.actor_username || '—'} → <b>{a.action}</b></span>
              {a.target_id && <span className="muted small"> {a.target_id.slice(0, 8)}…</span>}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
EOF

cat > src/styles.css << 'EOF'
:root {
  --bg: #0f1720; --panel: #17202b; --panel-2: #1e2937;
  --text: #e6edf5; --muted: #8b98a8; --accent: #3b82f6;
  --danger: #ef4444; --border: #263341;
  font-family: system-ui, "Segoe UI", Tahoma, sans-serif;
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); }
a { color: var(--accent); text-decoration: none; }
.muted { color: var(--muted); }
.small { font-size: 12px; }
.center { text-align: center; padding: 24px; }
.truncate { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.error { background: #4a1f24; color: #ffb4b4; padding: 8px 12px; border-radius: 6px; margin: 8px 0; }

.app { min-height: 100vh; }
.nav { display: flex; align-items: center; gap: 16px; padding: 10px 20px; background: var(--panel); border-bottom: 1px solid var(--border); position: sticky; top: 0; z-index: 10; flex-wrap: wrap; }
.brand { font-weight: 800; font-size: 22px; color: var(--text); }
.search { position: relative; }
.search input { background: var(--panel-2); border: 1px solid var(--border); color: var(--text); border-radius: 20px; padding: 8px 14px; width: 200px; outline: none; }
.search-drop { position: absolute; top: 110%; inset-inline-start: 0; background: var(--panel-2); border: 1px solid var(--border); border-radius: 8px; min-width: 260px; max-height: 320px; overflow: auto; z-index: 20; }
.search-item { padding: 8px 12px; cursor: pointer; }
.search-item:hover { background: var(--panel); }
.nav-links { display: flex; align-items: center; gap: 12px; margin-inline-start: auto; flex-wrap: wrap; }
.nav-links a { color: var(--muted); }
.nav-links a.active { color: var(--text); font-weight: 600; }

.main { max-width: 900px; margin: 20px auto; padding: 0 16px; }
.card { background: var(--panel); border: 1px solid var(--border); border-radius: 10px; padding: 16px; margin-bottom: 16px; }
.btn, .btn-ghost { border: none; padding: 8px 14px; border-radius: 8px; cursor: pointer; font: inherit; background: var(--accent); color: white; }
.btn-ghost { background: transparent; color: var(--text); border: 1px solid var(--border); }
.btn-ghost.active { color: var(--danger); border-color: var(--danger); }
.btn:disabled { opacity: 0.6; cursor: not-allowed; }
input, textarea, select { width: 100%; background: var(--panel-2); border: 1px solid var(--border); color: var(--text); border-radius: 8px; padding: 10px 12px; font: inherit; outline: none; margin: 6px 0; }
input:focus, textarea:focus { border-color: var(--accent); }

.auth-page { display: flex; justify-content: center; padding: 60px 16px; }
.auth-card { width: 100%; max-width: 380px; }
.auth-card h1 { margin: 0 0 8px; }

.composer textarea { resize: vertical; }
.composer-row { display: flex; align-items: center; gap: 10px; justify-content: flex-end; }
.preview { max-height: 320px; border-radius: 8px; margin: 8px 0; width: auto; }

.post-head { display: flex; align-items: center; gap: 12px; margin-bottom: 8px; }
.post-author { display: flex; align-items: center; gap: 12px; color: var(--text); }
.avatar { width: 40px; height: 40px; border-radius: 50%; object-fit: cover; background: var(--panel-2); }
.avatar.lg { width: 96px; height: 96px; }
.placeholder { display: inline-block; }
.post-body { margin: 8px 0; white-space: pre-wrap; }
.post-media { max-width: 100%; border-radius: 8px; margin: 8px 0; }
.post-actions { display: flex; gap: 8px; padding-top: 8px; border-top: 1px solid var(--border); }
.comments { padding-top: 8px; }
.comment { padding: 4px 0; }
.comment-form { display: flex; gap: 8px; margin-top: 8px; }
.comment-form input { margin: 0; }

.cover { width: 100%; height: 180px; object-fit: cover; border-radius: 8px; }
.profile-info { display: flex; gap: 16px; align-items: center; margin-top: -48px; padding: 0 16px; flex-wrap: wrap; }
.profile-info > div:first-of-type { flex: 1; min-width: 200px; }
.profile-actions { display: flex; gap: 8px; }
.edit-form { margin-top: 12px; }

.user-row { display: flex; align-items: center; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid var(--border); gap: 8px; flex-wrap: wrap; }
.user-row:last-child { border-bottom: none; }

.messages { display: grid; grid-template-columns: 280px 1fr; gap: 16px; }
.conv-list { max-height: 70vh; overflow: auto; }
.conv { padding: 8px; border-radius: 6px; cursor: pointer; }
.conv:hover, .conv.active { background: var(--panel-2); }
.chat { display: flex; flex-direction: column; height: 70vh; }
.chat-body { flex: 1; overflow: auto; padding: 8px 0; }
.msg { max-width: 70%; margin: 4px 0; padding: 8px 12px; border-radius: 12px; background: var(--panel-2); display: flex; gap: 8px; align-items: flex-end; flex-wrap: wrap; }
.msg.mine { margin-inline-start: auto; background: var(--accent); color: white; }
.chat-form { display: flex; gap: 8px; padding-top: 8px; border-top: 1px solid var(--border); }
.chat-form input { margin: 0; }

.notif { padding: 10px; border-bottom: 1px solid var(--border); cursor: pointer; }
.notif.unread { background: rgba(59,130,246,0.08); }
.sentinel { height: 1px; }
.pill { background: var(--panel-2); padding: 6px 12px; border-radius: 20px; color: var(--text); }

.tabs { display: flex; gap: 8px; margin: 12px 0; flex-wrap: wrap; }
.stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px; }
.stat { background: var(--panel-2); padding: 14px; border-radius: 8px; }
.stat .big { font-size: 26px; font-weight: 800; }
.audit-row { padding: 6px 0; border-bottom: 1px solid var(--border); }

@media (max-width: 720px) {
  .messages { grid-template-columns: 1fr; }
  .conv-list { max-height: 220px; }
  .search input { width: 140px; }
}
EOF

echo ""
echo "==================================================="
echo " CLIENT BOOTSTRAP COMPLETE"
echo "==================================================="
find . -type f -not -path './node_modules/*' | sort
echo "==================================================="
