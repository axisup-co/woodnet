const levels = ['debug', 'info', 'warn', 'error'];
const currentLevel = process.env.LOG_LEVEL || 'info';
const ts = () => new Date().toISOString();

function emit(level, msg, meta) {
  if (levels.indexOf(level) < levels.indexOf(currentLevel)) return;
  const line = `[${ts()}] ${level.toUpperCase()} ${msg}`;
  if (meta !== undefined) (level === 'error' ? console.error : console.log)(line, meta);
  else (level === 'error' ? console.error : console.log)(line);
}

export const log = {
  debug: (m, x) => emit('debug', m, x),
  info: (m, x) => emit('info', m, x),
  warn: (m, x) => emit('warn', m, x),
  error: (m, x) => emit('error', m, x),
};
