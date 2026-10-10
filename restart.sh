#!/data/data/com.termux/files/usr/bin/bash
pkill -9 -f node 2>/dev/null
sleep 1
pg_ctl -D $PREFIX/var/lib/postgresql status >/dev/null 2>&1 || \
  pg_ctl -D $PREFIX/var/lib/postgresql -l $PREFIX/var/lib/postgresql/logfile start
cd ~/woodnet/server && npm run dev
