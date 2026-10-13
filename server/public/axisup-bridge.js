(async () => {
  const token = localStorage.getItem('token');

  // ===== لا يوجد token: اعرض شاشة الدخول =====
  if (!token) return showLogin();

  const H = { Authorization: 'Bearer ' + token };
  const JH = { ...H, 'Content-Type': 'application/json' };

  // ===== تحقق من التوكن =====
  let me;
  try {
    const r = await fetch('/api/auth/me', { headers: H });
    if (!r.ok) throw 0;
    const d = await r.json();
    me = d.user;
  } catch {
    localStorage.removeItem('token');
    return showLogin();
  }

  // ===== حمّل البيانات =====
  CURRENT_USER.id = me.id;
  CURRENT_USER.username = me.username;
  CURRENT_USER.name = me.full_name || me.username;
  CURRENT_USER.headline = '@' + me.username + ' · ' + (me.role || 'user');
  CURRENT_USER.avatar = me.avatar_url || 'https://ui-avatars.com/api/?name=' + encodeURIComponent(me.username) + '&background=0A1A24&color=00B074&bold=true&size=200';

  try {
    const r = await fetch('/api/posts/feed?limit=30', { headers: H });
    if (r.ok) {
      const d = await r.json();
      POSTS.length = 0;
      (d.items || []).forEach(p => POSTS.push({
        id: p.id, userId: p.author_id,
        authorUsername: p.author_username, authorName: p.author_full_name || p.author_username,
        authorAvatar: p.author_avatar || 'https://ui-avatars.com/api/?name=' + encodeURIComponent(p.author_username) + '&background=00B074&color=fff&bold=true&size=200',
        time: timeAgo(p.created_at), text: p.content || '', image: p.media_url || '',
        likes: p.like_count || 0, shares: 0, isLiked: !!p.liked_by_me,
        showComments: false, comments: [],
      }));
    }
  } catch {}

  try {
    const r = await fetch('/api/friends', { headers: H });
    if (r.ok) {
      const d = await r.json();
      CONTACTS.length = 0;
      (d.friends || []).forEach(f => CONTACTS.push({
        id: f.id, name: f.full_name || f.username, username: f.username,
        avatar: f.avatar_url || 'https://ui-avatars.com/api/?name=' + encodeURIComponent(f.username) + '&background=00B074&color=fff&bold=true&size=200',
        role: '@' + f.username, online: false, mutual: 0, botimId: '',
      }));
    }
  } catch {}

  try {
    const r = await fetch('/api/messages/conversations', { headers: H });
    if (r.ok) {
      const d = await r.json();
      CHATS.length = 0;
      (d.conversations || []).forEach(c => CHATS.push({
        id: c.id, userId: c.peer && c.peer.id,
        peerName: (c.peer && (c.peer.full_name || c.peer.username)) || '—',
        peerUsername: c.peer && c.peer.username,
        peerAvatar: (c.peer && c.peer.avatar_url) || 'https://ui-avatars.com/api/?name=U&background=0A1A24&color=00B074&bold=true',
        unread: 0, messages: [],
      }));
    }
  } catch {}

  const _orig = window.getUser;
  window.getUser = function (id) {
    if (id === 'me' || id === CURRENT_USER.id) return CURRENT_USER;
    const p = POSTS.find(x => x.userId === id);
    if (p && p.authorName) return { name: p.authorName, avatar: p.authorAvatar, role: '@' + p.authorUsername, username: p.authorUsername, online: false, botimId: '' };
    const c = CHATS.find(x => x.userId === id);
    if (c && c.peerName) return { name: c.peerName, avatar: c.peerAvatar, role: '@' + c.peerUsername, username: c.peerUsername, online: false, botimId: '' };
    const ct = CONTACTS.find(x => x.id === id);
    if (ct) return ct;
    return _orig(id);
  };

  window.toggleLike = async function (postId) {
    const p = POSTS.find(x => x.id === postId);
    if (!p) return;
    try {
      if (p.isLiked) {
        await fetch('/api/posts/' + postId + '/like', { method: 'DELETE', headers: H });
        p.isLiked = false; p.likes = Math.max(0, p.likes - 1);
      } else {
        await fetch('/api/posts/' + postId + '/like', { method: 'POST', headers: H });
        p.isLiked = true; p.likes += 1;
      }
      renderApp();
      toast(p.isLiked ? 'أعجبك 👍' : 'أُلغي الإعجاب');
    } catch { toast('خطأ'); }
  };

  window.createPost = async function () {
    const ta = document.getElementById('composerTextInput');
    if (!ta) return;
    const txt = ta.value.trim();
    if (!txt) { toast('اكتب نصاً'); return; }
    try {
      const r = await fetch('/api/posts', { method: 'POST', headers: JH, body: JSON.stringify({ content: txt }) });
      if (!r.ok) throw 0;
      const { post } = await r.json();
      POSTS.unshift({
        id: post.id, userId: post.author_id,
        authorUsername: CURRENT_USER.username, authorName: CURRENT_USER.name, authorAvatar: CURRENT_USER.avatar,
        time: 'الآن', text: post.content, image: '', likes: 0, shares: 0,
        isLiked: false, showComments: false, comments: [],
      });
      ta.value = '';
      renderApp();
      toast('تم النشر 🚀');
    } catch { toast('خطأ'); }
  };

  window.addCommentToPost = async function (postId) {
    const inp = document.getElementById('commentInput-' + postId);
    if (!inp || !inp.value.trim()) return;
    try {
      const r = await fetch('/api/posts/' + postId + '/comments', { method: 'POST', headers: JH, body: JSON.stringify({ content: inp.value.trim() }) });
      if (!r.ok) throw 0;
      const { comment } = await r.json();
      const p = POSTS.find(x => x.id === postId);
      if (p) { p.comments.push({ userId: CURRENT_USER.id, text: comment.content }); p.showComments = true; }
      inp.value = '';
      renderApp();
      toast('تم التعليق 💬');
    } catch { toast('خطأ'); }
  };

  window.openChatRoom = async function (chatId) {
    state.activeChatId = chatId;
    const c = CHATS.find(x => x.id === chatId);
    if (c) c.unread = 0;
    if (state.appMode === 'mobile') state.mobileChatOpen = true;
    else state.activeView = 'chat';
    renderApp();
    if (!c) return;
    try {
      const r = await fetch('/api/messages/conversations/' + chatId + '/messages', { headers: H });
      if (!r.ok) return;
      const d = await r.json();
      c.messages = (d.messages || []).map(m => ({
        from: m.sender_id === CURRENT_USER.id ? 'me' : 'them',
        text: m.body,
        time: new Date(m.created_at).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' }),
      }));
      renderApp();
    } catch {}
  };

  window.sendChatMessage = async function () {
    const inp = document.getElementById('activeChatInput');
    if (!inp || !inp.value.trim()) return;
    const text = inp.value.trim();
    const cid = state.activeChatId;
    const c = CHATS.find(x => x.id === cid);
    if (!c) return;
    try {
      const r = await fetch('/api/messages/conversations/' + cid + '/messages', { method: 'POST', headers: JH, body: JSON.stringify({ body: text }) });
      if (!r.ok) throw 0;
      c.messages.push({ from: 'me', text, time: new Date().toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' }) });
      inp.value = '';
      playTone('msg');
      renderApp();
    } catch { toast('خطأ'); }
  };

  function timeAgo(iso) {
    const s = (Date.now() - new Date(iso).getTime()) / 1000;
    if (s < 60) return 'الآن';
    if (s < 3600) return 'منذ ' + Math.floor(s / 60) + ' دقيقة';
    if (s < 86400) return 'منذ ' + Math.floor(s / 3600) + ' ساعة';
    if (s < 604800) return 'منذ ' + Math.floor(s / 86400) + ' يوم';
    return new Date(iso).toLocaleDateString('ar-EG');
  }

  if (typeof renderApp === 'function') renderApp();

  if (!document.getElementById('axisup-logout')) {
    const profBtn = document.querySelector('header button[onclick*="switchView(\'profile\')"]');
    if (profBtn) {
      const b = document.createElement('button');
      b.id = 'axisup-logout';
      b.title = 'خروج';
      b.innerHTML = '<i class="fa-solid fa-right-from-bracket"></i>';
      b.className = 'w-10 h-10 rounded-xl bg-ink/5 hover:bg-coral hover:text-white flex items-center justify-center text-ink/70 transition';
      b.onclick = () => { localStorage.removeItem('token'); location.reload(); };
      profBtn.parentNode.insertBefore(b, profBtn);
    }
  }
})();


/* ===== شاشة الدخول — بلا innerHTML scripts ===== */
function showLogin() {
  document.body.innerHTML = '<div style="min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px;background:linear-gradient(135deg,#0A1A24 0%,#0F2634 100%);font-family:Cairo,system-ui,sans-serif"><form id="axisup-login" style="background:#132836;border:1px solid #263341;border-radius:20px;padding:32px 24px;width:100%;max-width:380px;box-shadow:0 20px 60px -20px rgba(0,176,116,.4)"><div style="display:flex;align-items:center;gap:12px;justify-content:center;margin-bottom:8px"><img src="/axis-up-logo.png" alt="Axis Up" style="width:52px;height:52px;object-fit:contain;background:#fff;border-radius:14px;padding:6px"><h1 style="font-size:24px;font-weight:900;margin:0;color:#E6EDF5">Axis<span style="color:#00B074">Up</span></h1></div><div style="text-align:center;color:#8b98a8;font-size:13px;margin-bottom:24px">سجّل دخولك للمتابعة</div><div id="axisup-err" style="display:none;background:#4a1f24;color:#ffb4b4;padding:10px 14px;border-radius:10px;font-size:13px;margin-bottom:12px"></div><input id="axisup-em" type="email" placeholder="البريد الإلكتروني" required autocomplete="username" style="width:100%;padding:12px 14px;background:#0F2634;border:1px solid #263341;border-radius:12px;color:#E6EDF5;font-size:14px;margin:6px 0;outline:none;box-sizing:border-box;font-family:inherit"><input id="axisup-pw" type="password" placeholder="كلمة المرور" required autocomplete="current-password" style="width:100%;padding:12px 14px;background:#0F2634;border:1px solid #263341;border-radius:12px;color:#E6EDF5;font-size:14px;margin:6px 0;outline:none;box-sizing:border-box;font-family:inherit"><button id="axisup-go" type="submit" style="width:100%;padding:12px;background:#00B074;color:#fff;border:none;border-radius:12px;font-weight:800;font-size:15px;margin-top:12px;cursor:pointer;font-family:inherit">دخول</button><div style="text-align:center;color:#8b98a8;font-size:11px;margin-top:20px">Axis Up · منصة موحدة</div></form></div>';

  document.getElementById('axisup-login').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const err = document.getElementById('axisup-err');
    const btn = document.getElementById('axisup-go');
    err.style.display = 'none';
    btn.disabled = true;
    btn.textContent = '...';
    try {
      const r = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: document.getElementById('axisup-em').value.trim(),
          password: document.getElementById('axisup-pw').value,
        }),
      });
      const d = await r.json();
      if (!r.ok || !d.token) throw new Error(d.message || 'فشل الدخول');
      localStorage.setItem('token', d.token);
      location.reload();
    } catch (e) {
      err.textContent = e.message || 'خطأ';
      err.style.display = 'block';
      btn.disabled = false;
      btn.textContent = 'دخول';
    }
  });
}

/* ===== شاشة الدخول — بلا innerHTML scripts ===== */
function showLogin() {
  document.body.innerHTML = '<div style="min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px;background:linear-gradient(135deg,#0A1A24 0%,#0F2634 100%);font-family:Cairo,system-ui,sans-serif"><form id="axisup-login" style="background:#132836;border:1px solid #263341;border-radius:20px;padding:32px 24px;width:100%;max-width:380px;box-shadow:0 20px 60px -20px rgba(0,176,116,.4)"><div style="display:flex;align-items:center;gap:12px;justify-content:center;margin-bottom:8px"><img src="/axis-up-logo.png" alt="Axis Up" style="width:52px;height:52px;object-fit:contain;background:#fff;border-radius:14px;padding:6px"><h1 style="font-size:24px;font-weight:900;margin:0;color:#E6EDF5">Axis<span style="color:#00B074">Up</span></h1></div><div style="text-align:center;color:#8b98a8;font-size:13px;margin-bottom:24px">سجّل دخولك للمتابعة</div><div id="axisup-err" style="display:none;background:#4a1f24;color:#ffb4b4;padding:10px 14px;border-radius:10px;font-size:13px;margin-bottom:12px"></div><input id="axisup-em" type="email" placeholder="البريد الإلكتروني" required autocomplete="username" style="width:100%;padding:12px 14px;background:#0F2634;border:1px solid #263341;border-radius:12px;color:#E6EDF5;font-size:14px;margin:6px 0;outline:none;box-sizing:border-box;font-family:inherit"><input id="axisup-pw" type="password" placeholder="كلمة المرور" required autocomplete="current-password" style="width:100%;padding:12px 14px;background:#0F2634;border:1px solid #263341;border-radius:12px;color:#E6EDF5;font-size:14px;margin:6px 0;outline:none;box-sizing:border-box;font-family:inherit"><button id="axisup-go" type="submit" style="width:100%;padding:12px;background:#00B074;color:#fff;border:none;border-radius:12px;font-weight:800;font-size:15px;margin-top:12px;cursor:pointer;font-family:inherit">دخول</button><div style="text-align:center;color:#8b98a8;font-size:11px;margin-top:20px">Axis Up · منصة موحدة</div></form></div>';

  document.getElementById('axisup-login').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const err = document.getElementById('axisup-err');
    const btn = document.getElementById('axisup-go');
    err.style.display = 'none';
    btn.disabled = true;
    btn.textContent = '...';
    try {
      const r = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: document.getElementById('axisup-em').value.trim(),
          password: document.getElementById('axisup-pw').value,
        }),
      });
      const d = await r.json();
      if (!r.ok || !d.token) throw new Error(d.message || 'فشل الدخول');
      localStorage.setItem('token', d.token);
      location.reload();
    } catch (e) {
      err.textContent = e.message || 'خطأ';
      err.style.display = 'block';
      btn.disabled = false;
      btn.textContent = 'دخول';
    }
  });
}
