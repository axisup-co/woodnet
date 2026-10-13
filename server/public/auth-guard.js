(async () => {
  const token = localStorage.getItem('token');
  if (!token) { location.href = '/login.html'; return; }
  try {
    const r = await fetch('/api/auth/me', { headers: { Authorization: 'Bearer ' + token } });
    if (!r.ok) { localStorage.removeItem('token'); location.href = '/login.html'; return; }
    const { user } = await r.json();
    if (typeof CURRENT_USER !== 'undefined') {
      CURRENT_USER.name = user.full_name || user.username;
      CURRENT_USER.headline = '@' + user.username + ' · ' + (user.role || 'user');
      if (user.avatar_url) CURRENT_USER.avatar = user.avatar_url;
    }
    if (typeof renderApp === 'function') renderApp();
  } catch (e) {
    localStorage.removeItem('token');
    location.href = '/login.html';
  }
})();
