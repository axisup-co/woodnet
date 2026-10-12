const $ = (s) => document.querySelector(s);
const $$ = (s) => document.querySelectorAll(s);
const esc = (s) => (s == null ? '' : String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])));
const tk = { g: () => localStorage.getItem('token'), s: (t) => localStorage.setItem('token', t), c: () => localStorage.removeItem('token') };

async function api(path, opts = {}) {
  const r = await fetch(path, {
    method: opts.method || 'GET',
    headers: { ...(opts.body ? {'Content-Type':'application/json'} : {}), ...(tk.g() ? {Authorization: 'Bearer ' + tk.g()} : {}) },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  if (r.status === 204) return null;
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(d.message || r.statusText);
  return d;
}

let me = null;
const pages = {};

function show(name) {
  ['feed','friends','messages','notifications','admin'].forEach(p => $('#page-'+p).classList.add('hidden'));
  if (name) $('#page-'+name).classList.remove('hidden');
  $$('nav button[data-page]').forEach(b => b.classList.toggle('on', b.dataset.page === name));
  if (name && pages[name]) pages[name]();
}

async function boot() {
  if (!tk.g()) return renderAuth('login');
  try {
    const { user } = await api('/api/auth/me');
    me = user;
    $('#nav').classList.remove('hidden');
    $('#page-auth').classList.add('hidden');
    $('#who').textContent = '@' + user.username + ' · ' + user.role;
    show('feed');
  } catch { tk.c(); renderAuth('login'); }
}

function renderAuth(mode) {
  $('#nav').classList.add('hidden');
  $('#page-auth').classList.remove('hidden');
  const isL = mode === 'login';
  $('#auth-card').innerHTML = `
    <h2 style="margin:0 0 8px">${isL ? 'تسجيل الدخول' : 'إنشاء حساب'}</h2>
    <div id="aerr" class="err hidden"></div>
    ${isL ? '' : '<input id="f-user" placeholder="اسم المستخدم">'}
    ${isL ? '' : '<input id="f-name" placeholder="الاسم الكامل">'}
    <input id="f-email" type="email" placeholder="البريد">
    <input id="f-pass" type="password" placeholder="كلمة المرور">
    <div class="row end" style="margin-top:8px"><button class="btn-p" id="ago">${isL ? 'دخول' : 'تسجيل'}</button></div>
    <p class="muted" style="margin-top:10px">${isL ? 'ليس لديك حساب؟ <a href="#" id="toreg">سجل</a>' : 'لديك حساب؟ <a href="#" id="tolog">ادخل</a>'}</p>`;
  $('#toreg')?.addEventListener('click', e => { e.preventDefault(); renderAuth('register'); });
  $('#tolog')?.addEventListener('click', e => { e.preventDefault(); renderAuth('login'); });
  $('#ago').addEventListener('click', async () => {
    const er = $('#aerr'); er.classList.add('hidden');
    try {
      const email = $('#f-email').value.trim(), password = $('#f-pass').value;
      const r = isL
        ? await api('/api/auth/login', { method: 'POST', body: { email, password } })
        : await api('/api/auth/register', { method: 'POST', body: { email, password, username: $('#f-user').value.trim(), fullName: $('#f-name').value.trim() } });
      tk.s(r.token); boot();
    } catch (e) { er.textContent = e.message; er.classList.remove('hidden'); }
  });
}

pages.feed = async function () {
  const el = $('#page-feed');
  el.innerHTML = `
    <div class="card">
      <textarea id="pc-body" rows="3" placeholder="بماذا تفكر؟"></textarea>
      <div class="row end"><button class="btn-p" id="pc-go">نشر</button></div>
    </div>
    <div id="feed-list"><div class="center muted">...</div></div>`;
  $('#pc-go').addEventListener('click', async () => {
    const content = $('#pc-body').value.trim();
    if (!content) return;
    await api('/api/posts', { method: 'POST', body: { content } });
    $('#pc-body').value = '';
    pages.feed();
  });
  try {
    const { items } = await api('/api/posts/feed?limit=20');
    const list = $('#feed-list');
    if (!items.length) return list.innerHTML = '<div class="card center muted">لا منشورات بعد</div>';
    list.innerHTML = items.map(renderPost).join('');
    items.forEach(p => wirePost(p));
  } catch (e) { $('#feed-list').innerHTML = `<div class="card err">${esc(e.message)}</div>`; }
};

function renderPost(p) {
  const author = esc(p.author_username);
  return `<article class="card" data-id="${p.id}">
    <div class="post-head">
      <a href="#" data-user="${author}" style="color:inherit">
        ${p.author_avatar ? `<img class="avatar" src="${esc(p.author_avatar)}">` : '<span class="avatar"></span>'}
        <b style="margin-right:8px">${esc(p.author_full_name || author)}</b>
        <span class="muted small">@${author}</span>
      </a>
      ${p.author_username === (me?.username) ? '<button class="btn-del btn" style="font-size:12px">حذف</button>' : ''}
    </div>
    ${p.content ? `<p class="post-body">${esc(p.content)}</p>` : ''}
    ${p.media_url ? `<img class="post-media" src="${esc(p.media_url)}">` : ''}
    <div class="post-actions">
      <button class="btn-like btn${p.liked_by_me ? ' on' : ''}" style="${p.liked_by_me ? 'color:#ef4444;border-color:#ef4444' : ''}">❤ <span>${p.like_count || 0}</span></button>
      <button class="btn-cm btn">💬 <span>${p.comment_count || 0}</span></button>
    </div>
    <div class="cm-wrap hidden" style="padding-top:8px">
      <div class="cm-list"></div>
      <div class="row"><input class="cm-in" placeholder="اكتب تعليقاً"><button class="btn-p btn-cm-go">إرسال</button></div>
    </div>
  </article>`;
}

function wirePost(p) {
  const card = document.querySelector(`[data-id="${p.id}"]`);
  if (!card) return;
  card.querySelector('.btn-del')?.addEventListener('click', async () => {
    if (!confirm('حذف المنشور؟')) return;
    await api('/api/posts/' + p.id, { method: 'DELETE' });
    card.remove();
  });
  const lk = card.querySelector('.btn-like');
  lk.addEventListener('click', async () => {
    const on = lk.classList.contains('on');
    if (on) { await api('/api/posts/' + p.id + '/like', { method: 'DELETE' }); lk.classList.remove('on'); lk.style.cssText = ''; }
    else { await api('/api/posts/' + p.id + '/like', { method: 'POST' }); lk.classList.add('on'); lk.style.cssText = 'color:#ef4444;border-color:#ef4444'; }
    const sp = lk.querySelector('span');
    sp.textContent = Math.max(0, +sp.textContent + (on ? -1 : 1));
  });
  const cmWrap = card.querySelector('.cm-wrap');
  card.querySelector('.btn-cm').addEventListener('click', async () => {
    cmWrap.classList.toggle('hidden');
    if (!cmWrap.classList.contains('hidden')) {
      const { comments } = await api('/api/posts/' + p.id + '/comments');
      cmWrap.querySelector('.cm-list').innerHTML = comments.map(c =>
        `<div class="comment"><a href="#" class="muted small">@${esc(c.username)}</a> ${esc(c.content)}</div>`).join('');
    }
  });
  cmWrap.querySelector('.btn-cm-go').addEventListener('click', async () => {
    const inp = cmWrap.querySelector('.cm-in');
    if (!inp.value.trim()) return;
    await api('/api/posts/' + p.id + '/comments', { method: 'POST', body: { content: inp.value.trim() } });
    inp.value = '';
    cmWrap.querySelector('.btn-cm').click();
    cmWrap.classList.remove('hidden');
    const b = card.querySelector('.btn-cm span');
    b.textContent = +b.textContent + 1;
  });
}

$('#logout').addEventListener('click', () => { tk.c(); me = null; renderAuth('login'); });
$$('nav button[data-page]').forEach(b => b.addEventListener('click', () => show(b.dataset.page)));
window.addEventListener('DOMContentLoaded', boot);

pages.friends = async function () {
  const el = $('#page-friends');
  el.innerHTML = '<div class="center muted">...</div>';
  try {
    const [{ friends }, { requests }] = await Promise.all([api('/api/friends'), api('/api/friends/requests')]);
    el.innerHTML = `
      <div class="card"><h3 style="margin:0 0 8px">طلبات الصداقة</h3>
        ${requests.length === 0 ? '<p class="muted">لا طلبات</p>' : requests.map(r => `
          <div class="row" style="justify-content:space-between;border-bottom:1px solid var(--border);padding:6px 0">
            <span>@${esc(r.username)} <span class="muted small">${esc(r.full_name || '')}</span></span>
            <span><button class="btn-p" data-acc="${r.id}">قبول</button> <button class="btn" data-rej="${r.id}">رفض</button></span>
          </div>`).join('')}
      </div>
      <div class="card"><h3 style="margin:0 0 8px">أصدقائي (${friends.length})</h3>
        ${friends.length === 0 ? '<p class="muted">لا أصدقاء</p>' : friends.map(f => `
          <div class="row" style="justify-content:space-between;border-bottom:1px solid var(--border);padding:6px 0">
            <span>@${esc(f.username)} <span class="muted small">${esc(f.full_name || '')}</span></span>
            <button class="btn" data-chat="${f.id}">رسالة</button>
          </div>`).join('')}
      </div>`;
    el.querySelectorAll('[data-acc]').forEach(b => b.addEventListener('click', async () => {
      await api('/api/friends/respond', { method: 'POST', body: { requestId: b.dataset.acc, accept: true } });
      pages.friends();
    }));
    el.querySelectorAll('[data-rej]').forEach(b => b.addEventListener('click', async () => {
      await api('/api/friends/respond', { method: 'POST', body: { requestId: b.dataset.rej, accept: false } });
      pages.friends();
    }));
    el.querySelectorAll('[data-chat]').forEach(b => b.addEventListener('click', async () => {
      const { conversationId } = await api('/api/messages/conversation', { method: 'POST', body: { peerId: b.dataset.chat } });
      show('messages');
      setTimeout(() => openConv(conversationId), 50);
    }));
  } catch (e) { el.innerHTML = `<div class="card err">${esc(e.message)}</div>`; }
};

let activeConv = null;
async function openConv(id) {
  activeConv = id;
  const list = $('#conv-list');
  if (list) {
    list.querySelectorAll('.conv').forEach(c => c.classList.toggle('on', c.dataset.id === id));
    list.querySelectorAll('.conv').forEach(c => c.classList.toggle('on', c.dataset.id === id));
  }
  try {
    const { messages } = await api('/api/messages/conversations/' + id + '/messages');
    const body = $('#chat-body');
    body.innerHTML = messages.map(m => `
      <div class="msg-wrap"><div class="msg${m.sender_id === me.id ? ' mine' : ''}">
        ${esc(m.body)}<span class="muted small" style="margin-right:6px"> ${new Date(m.created_at).toLocaleTimeString('ar')}</span>
      </div></div>`).join('');
    body.scrollTop = body.scrollHeight;
  } catch (e) { $('#chat-body').innerHTML = `<div class="err">${esc(e.message)}</div>`; }
}

pages.messages = async function () {
  const el = $('#page-messages');
  el.innerHTML = `
    <div class="messages">
      <div class="card conv-list" id="conv-list"><h3 style="margin:0 0 8px">المحادثات</h3><div class="muted center small">...</div></div>
      <div class="card">
        <div class="chat-body" id="chat-body"><div class="muted center">اختر محادثة</div></div>
        <div class="row"><input id="m-in" placeholder="اكتب..."><button class="btn-p" id="m-go">إرسال</button></div>
      </div>
    </div>`;
  try {
    const { conversations } = await api('/api/messages/conversations');
    const list = $('#conv-list');
    if (!conversations.length) list.innerHTML = '<h3 style="margin:0 0 8px">المحادثات</h3><p class="muted small">لا محادثات</p>';
    else {
      list.innerHTML = '<h3 style="margin:0 0 8px">المحادثات</h3>' + conversations.map(c => `
        <div class="conv" data-id="${c.id}">
          <div><b>${esc(c.peer?.full_name || c.peer?.username || '—')}</b></div>
          <div class="muted small" style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(c.last_message || '')}</div>
        </div>`).join('');
      list.querySelectorAll('.conv').forEach(c => c.addEventListener('click', () => openConv(c.dataset.id)));
    }
    if (activeConv) openConv(activeConv);
    $('#m-go').addEventListener('click', async () => {
      const inp = $('#m-in');
      if (!inp.value.trim() || !activeConv) return;
      await api('/api/messages/conversations/' + activeConv + '/messages', { method: 'POST', body: { body: inp.value.trim() } });
      inp.value = '';
      openConv(activeConv);
    });
  } catch (e) { el.innerHTML = `<div class="card err">${esc(e.message)}</div>`; }
};

pages.notifications = async function () {
  const el = $('#page-notifications');
  el.innerHTML = '<div class="center muted">...</div>';
  const labels = { like: 'أعجب بمنشورك', comment: 'علّق على منشورك', friend_request: 'أرسل طلب صداقة', friend_accept: 'قبل صداقتك' };
  try {
    const { notifications } = await api('/api/notifications');
    if (!notifications.length) return el.innerHTML = '<div class="card center muted">لا إشعارات</div>';
    el.innerHTML = `<div class="card">${notifications.map(n => `
      <div class="notif${n.read_at ? '' : ' un'}" data-id="${n.id}">
        ${n.actor_username ? `<b>@${esc(n.actor_username)}</b> ` : ''}${esc(labels[n.type] || n.type)}
        <span class="muted small"> · ${new Date(n.created_at).toLocaleString('ar')}</span>
      </div>`).join('')}</div>`;
    el.querySelectorAll('.notif').forEach(el2 => el2.addEventListener('click', async () => {
      if (el2.classList.contains('un')) {
        await api('/api/notifications/' + el2.dataset.id + '/read', { method: 'POST' });
        el2.classList.remove('un');
      }
    }));
  } catch (e) { el.innerHTML = `<div class="card err">${esc(e.message)}</div>`; }
};

pages.admin = async function () {
  const el = $('#page-admin');
  el.innerHTML = `
    <div class="card">
      <h2 style="margin:0 0 8px">لوحة التحكم</h2>
      <div class="tabs">
        <button class="btn" data-t="stats">إحصائيات</button>
        <button class="btn" data-t="users">مستخدمون</button>
        <button class="btn" data-t="audit">سجل التدقيق</button>
      </div>
      <div id="adm-body" class="muted center small">...</div>
    </div>`;
  const btn = (t) => {
    el.querySelectorAll('.tabs button').forEach(b => b.classList.toggle('on', b.dataset.t === t));
    el.querySelectorAll('.tabs button').forEach(b => { b.style.background = b.dataset.t === t ? 'var(--accent)' : 'transparent'; b.style.color = b.dataset.t === t ? '#fff' : 'var(--text)'; });
  };
  async function loadTab(t) {
    btn(t);
    const body = $('#adm-body');
    body.innerHTML = '<div class="center muted">...</div>';
    try {
      if (t === 'stats') {
        const { stats } = await api('/api/admin/stats');
        body.innerHTML = '<div class="stats">' + Object.entries(stats).map(([k, v]) => `<div class="stat"><div class="muted small">${esc(k)}</div><b>${v}</b></div>`).join('') + '</div>';
      } else if (t === 'users') {
        const { users } = await api('/api/admin/users?limit=100');
        body.innerHTML = users.map(u => `
          <div class="row" style="justify-content:space-between;border-bottom:1px solid var(--border);padding:6px 0">
            <span>@${esc(u.username)} <span class="muted small">${esc(u.email)}</span></span>
            <select data-uid="${u.id}" style="width:auto">
              ${['user','moderator','admin','owner'].map(r => `<option value="${r}"${u.role === r ? ' selected' : ''}>${r}</option>`).join('')}
            </select>
          </div>`).join('');
        body.querySelectorAll('select[data-uid]').forEach(s => s.addEventListener('change', async () => {
          try { await api('/api/admin/users/' + s.dataset.uid + '/role', { method: 'PATCH', body: { role: s.value } }); }
          catch (e) { alert(e.message); loadTab('users'); }
        }));
      } else {
        const { audit } = await api('/api/admin/audit?limit=100');
        body.innerHTML = audit.map(a => `
          <div class="small" style="border-bottom:1px solid var(--border);padding:5px 0">
            <span class="muted">${new Date(a.created_at).toLocaleString('ar')}</span>
            · ${esc(a.actor_username || '—')} → <b>${esc(a.action)}</b>
          </div>`).join('') || '<div class="muted">لا سجل</div>';
      }
    } catch (e) { body.innerHTML = `<div class="err">${esc(e.message)}</div>`; }
  }
  el.querySelectorAll('.tabs button').forEach(b => b.addEventListener('click', () => loadTab(b.dataset.t)));
  loadTab('stats');
};

/* ===== Profile + Pathname Router ===== */
const _origShow = show;
show = function(name) {
  ['feed','friends','messages','notifications','admin','profile'].forEach(p => {
    const el = $('#page-' + p); if (el) el.classList.add('hidden');
  });
  if (name) { const el = $('#page-' + name); if (el) el.classList.remove('hidden'); }
  $$('nav button[data-page]').forEach(b => b.classList.toggle('on', b.dataset.page === name));
  if (name && pages[name] && name !== 'profile') pages[name]();
};

pages.profile = async function(username) {
  const el = $('#page-profile');
  el.innerHTML = '<div class="center muted">...</div>';
  try {
    const data = await api('/api/users/' + encodeURIComponent(username));
    const u = data.user, posts = data.posts || [], stats = data.stats || {};
    el.innerHTML = `
      <div class="card">
        <div class="row" style="gap:12px;flex-wrap:wrap">
          ${u.avatar_url ? `<img src="${esc(u.avatar_url)}" class="avatar" style="width:80px;height:80px">` : '<span class="avatar" style="width:80px;height:80px;display:inline-block"></span>'}
          <div style="flex:1;min-width:180px">
            <h2 style="margin:0">${esc(u.full_name || u.username)}</h2>
            <div class="muted small">@${esc(u.username)}</div>
            ${u.bio ? `<p>${esc(u.bio)}</p>` : ''}
            <div class="muted small">${stats.friend_count || 0} صديق · ${stats.post_count || 0} منشور</div>
          </div>
          ${me && me.username === u.username ? '' : `
            <button class="btn-p" id="pf-add">إضافة صديق</button>
            <button class="btn" id="pf-chat">رسالة</button>`}
        </div>
      </div>
      <div>${posts.map(renderPost).join('') || '<div class="card muted center">لا منشورات</div>'}</div>`;
    posts.forEach(wirePost);
    const addBtn = $('#pf-add'), chatBtn = $('#pf-chat');
    if (addBtn) addBtn.addEventListener('click', async () => {
      try { await api('/api/friends/request', { method: 'POST', body: { addresseeId: u.id } }); alert('تم إرسال الطلب'); }
      catch(e) { alert(e.message); }
    });
    if (chatBtn) chatBtn.addEventListener('click', async () => {
      const { conversationId } = await api('/api/messages/conversation', { method: 'POST', body: { peerId: u.id } });
      history.pushState({}, '', '/messages/' + conversationId);
      route();
    });
  } catch(e) { el.innerHTML = `<div class="card err">${esc(e.message)}</div>`; }
};

function route() {
  const p = location.pathname;
  if (p === '/' || p === '') show('feed');
  else if (p === '/friends') show('friends');
  else if (p === '/messages') show('messages');
  else if (p.startsWith('/messages/')) { show('messages'); if (typeof openConv === 'function') setTimeout(() => openConv(p.split('/').pop()), 50); }
  else if (p === '/notifications') show('notifications');
  else if (p === '/admin') show('admin');
  else if (p.startsWith('/u/')) { show('profile'); pages.profile(decodeURIComponent(p.slice(3))); }
  else show('feed');
}

window.addEventListener('DOMContentLoaded', () => setTimeout(route, 300));
window.addEventListener('popstate', route);

document.addEventListener('click', (e) => {
  const a = e.target.closest && e.target.closest('[data-user]');
  if (a) {
    e.preventDefault();
    const u = a.dataset.user;
    history.pushState({}, '', '/u/' + u);
    route();
  }
});
