import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from './pool.js';
import { log } from '../utils/logger.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function runSql(file) {
  const full = path.resolve(__dirname, file);
  const sql = fs.readFileSync(full, 'utf8');
  log.info(`applying ${file}`);
  await pool.query(sql);
}

async function main() {
  try {
    await runSql('schema.sql');
    await runSql('migrations/002_admin.sql');
    log.info('migrations complete');
    await pool.end();
    process.exit(0);
  } catch (e) {
    log.error('migration failed', e.message);
    await pool.end();
    process.exit(1);
  }
}

main();
