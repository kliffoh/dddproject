#!/usr/bin/env node
/*
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  DDD AI WORKFORCE MANAGEMENT SYSTEM  v6.0                        ║
 * ║  Digital Divide Data — Changing How the World Works.             ║
 * ║                                                                  ║
 * ║  Entry point: boot sequence + lifecycle management.              ║
 * ║    1. migrate (non-destructive)   4. HTTP + WebSocket            ║
 * ║    2. seed (empty DB only)        5. background jobs             ║
 * ║    3. warm the ML engine          6. graceful shutdown           ║
 * ╚══════════════════════════════════════════════════════════════════╝
 */
'use strict';

// scrypt runs on libuv's pool; widen it so a login rush never queues behind file I/O.
process.env.UV_THREADPOOL_SIZE = process.env.UV_THREADPOOL_SIZE || '16';

process.removeAllListeners('warning');
process.on('warning', (w) => { if (!(w.name === 'ExperimentalWarning' && /sqlite/i.test(w.message))) console.warn(w.message); });

const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const config = require('./src/config');
for (const d of Object.values(config.dirs)) fs.mkdirSync(d, { recursive: true });

const log = require('./src/core/logger');
const db = require('./src/db/database');
const { migrate } = require('./src/db/migrations');
const { seed } = require('./src/db/seed');
const engine = require('./src/services/chat/engine');
const { createApp } = require('./src/app');
const ws = require('./src/realtime/websocket');
const jobs = require('./src/jobs/scheduler');
const { eat } = require('./src/core/time');

function lanAddresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const x of list || []) if (x.family === 'IPv4' && !x.internal && !x.address.startsWith('169.254.')) out.push(x.address);
  }
  return out;
}

function writeSystemInfo(port) {
  const lan = lanAddresses();
  const info = [
    `DDD AI WORKFORCE MANAGEMENT SYSTEM v${config.version}`,
    'Digital Divide Data -- Changing How the World Works.',
    '='.repeat(60),
    `Startup   : ${eat()}`,
    `Port      : ${port}`,
    `Local URL : http://localhost:${port}`,
    ...lan.map(ip => `LAN URL   : http://${ip}:${port}`),
    `Public URL: ${config.publicUrl || '(not configured — run DDD_HOSTING)'}`,
    `Node.js   : ${process.version}  (${process.platform})`,
    `Database  : ${db.path}`,
    `Data Dir  : ${config.dirs.base}`,
    `Capacity  : ${config.maxEmployees} employees`,
    `AI Chat   : ${config.anthropicKey ? `Claude (${config.anthropicModel}) + retrieval` : 'Retrieval engine (set ANTHROPIC_API_KEY for generative answers)'}`
  ].join('\n');
  fs.writeFileSync(path.join(config.dirs.system, 'software_info.txt'), info + '\n');
  fs.appendFileSync(path.join(config.dirs.system, 'startup_history.txt'), `[${eat()}] v${config.version} started on port ${port} | LAN: ${lan.join(', ') || 'n/a'}\n`);
}

async function main() {
  migrate();
  await seed();
  engine.init();

  const server = http.createServer(createApp());
  server.keepAliveTimeout = 65000;        // > typical proxy idle timeout (Caddy/ALB 60 s)
  server.headersTimeout = 66000;
  server.requestTimeout = 120000;
  ws.attach(server);

  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      console.error(`\n  [FATAL] Port ${config.port} is already in use — is DDD already running?`);
      console.error('          Stop the other instance, or set PORT=<other> in .env\n');
    } else console.error('[FATAL]', err.message);
    process.exit(1);
  });

  server.listen(config.port, config.host, () => {
    writeSystemInfo(config.port);
    const bar = '═'.repeat(62);
    console.log(`\n  ${bar}\n   DDD AI WORKFORCE MANAGEMENT SYSTEM  v${config.version}\n   Digital Divide Data — Changing How the World Works.\n  ${bar}`);
    console.log(`   Local     http://localhost:${config.port}`);
    for (const ip of lanAddresses()) console.log(`   LAN       http://${ip}:${config.port}`);
    if (config.publicUrl) console.log(`   Public    ${config.publicUrl}`);
    console.log(`   Data      ${config.dirs.base}`);
    console.log(`   Capacity  ${config.maxEmployees} employees`);
    console.log(`   AI        ${config.anthropicKey ? 'Claude + retrieval' : 'Retrieval engine (EN + SW)'}`);
    console.log(`  ${bar}\n`);
  });
  jobs.start();

  // ─── Graceful shutdown: finish in-flight requests, close sockets, checkpoint DB ──
  let stopping = false;
  const shutdown = (code = 0, why = 'signal') => {
    if (stopping) return;
    stopping = true;
    log.info(`Shutting down (${why})…`);
    jobs.stop();
    setTimeout(() => process.exit(code), 10000).unref();
    server.close(() => { log.flush(); try { db.close(); } catch (_) {} process.exit(code); });
    for (const c of require('./src/services/presence').online.values()) for (const s of c.sockets) { try { s.close(1001, 'Server restarting'); } catch (_) {} }
  };
  process.on('SIGINT', () => shutdown(0, 'SIGINT'));
  process.on('SIGTERM', () => shutdown(0, 'SIGTERM'));
  // A crashed process should exit and be restarted by the supervisor (PM2/systemd/Docker),
  // not limp on in an unknown state.
  process.on('uncaughtException', (e) => { log.error('uncaughtException', e); shutdown(1, 'uncaughtException'); });
  process.on('unhandledRejection', (e) => log.error('unhandledRejection', e));
}

main().catch((e) => { console.error('[FATAL] Boot failed:', e); process.exit(1); });
