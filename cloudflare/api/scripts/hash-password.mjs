#!/usr/bin/env node
// Generates a PBKDF2-SHA256 hash string for ADMIN_PASSWORD_HASH (`wrangler secret put ADMIN_PASSWORD_HASH`).
// Usage: node scripts/hash-password.mjs
import { createInterface } from 'node:readline/promises';
import { randomBytes, pbkdf2Sync } from 'node:crypto';

const rl = createInterface({ input: process.stdin, output: process.stdout });
const password = await rl.question('Admin password to hash: ');
rl.close();

if (!password || password.length < 12) {
  console.error('Use a password of at least 12 characters.');
  process.exit(1);
}

const iterations = 100_000;
const salt = randomBytes(16);
const derived = pbkdf2Sync(password, salt, iterations, 32, 'sha256');
console.log(`pbkdf2_sha256$${iterations}$${salt.toString('hex')}$${derived.toString('hex')}`);
