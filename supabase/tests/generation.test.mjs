// Checks Create's server-side limits (migration 0003) and the AdMob callback signature check.
// Run: cd supabase/tests && npm install --no-save @electric-sql/pglite@0.3.4 && node generation.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'fs';
import { generateKeyPairSync, sign } from 'crypto';
import { verifyRewardCallback } from '../functions/_shared/admob.js';
const repo = new URL('../..', import.meta.url).pathname;
const ok = (c, m) => { if (!c) { console.error('FAIL', m); process.exitCode = 1 } else console.log('ok', m) };
const fails = async (p, m) => { try { await p; ok(false, m) } catch (e) { ok(true, m + ' (' + e.message.split('\n')[0] + ')') } };

// --- Limits ---
const db = new PGlite();
await db.exec(`create role anon; create role authenticated; grant usage on schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;`);
await db.exec(readFileSync(repo + '/supabase/migrations/0003_generation_limits.sql', 'utf8'));
const reward = (tx, install, nonce, age = '0') =>
  db.query(`insert into ad_rewards (transaction_id, install_id, nonce, created_at) values ($1, $2, $3, now() - $4::interval)`, [tx, install, nonce, age]);
const redeem = async (nonce, install, daily = 3, global = 100) =>
  (await db.query('select redeem_ad_reward($1, $2, $3, $4) as r', [nonce, install, daily, global])).rows[0].r;

ok(await redeem('n1', 'A') === 'no_reward', 'no ad watched: no generation');
await reward('t1', 'A', 'n1');
ok(await redeem('n1', 'B') === 'no_reward', "another install can't spend A's ad");
ok(await redeem('n1', 'A') === 'ok', 'a verified ad buys one generation');
ok(await redeem('n1', 'A') === 'no_reward', 'the same ad only once');
await db.query('select refund_ad_reward($1, $2)', ['n1', 'A']);
ok(await redeem('n1', 'A') === 'ok', 'a refunded ad can be spent again');
await reward('t-old', 'A', 'old', '2 hours');
ok(await redeem('old', 'A') === 'no_reward', 'ads older than an hour have expired');
await reward('t2', 'A', 'n2'); await reward('t3', 'A', 'n3'); await reward('t4', 'A', 'n4');
ok(await redeem('n2', 'A') === 'ok' && await redeem('n3', 'A') === 'ok', 'three a day');
ok(await redeem('n4', 'A') === 'daily_limit', 'the fourth is over the daily limit');
await db.query(`update ad_rewards set redeemed_at = now() - interval '1 day' where install_id = 'A' and redeemed_at is not null`);
ok(await redeem('n4', 'A') === 'ok', "yesterday's generations don't count today");
await reward('t5', 'C', 'n5');
ok(await redeem('n5', 'C', 3, 1) === 'global_limit', 'the global cap stops everyone');
await fails(db.query(`insert into ad_rewards (transaction_id, install_id, nonce) values ('t1', 'A', 'x')`), 'a retried callback is stored once');
await fails(db.query(`insert into generation_reports (install_id, prompt, reason) values ('A', 'x', 'spam')`), 'unknown report reasons are rejected');
await db.query(`insert into generation_reports (install_id, prompt, reason) values ('A', 'a red fox', 'other')`);
ok(true, 'a report is stored');
const asAnon = async (sql) => { await db.exec('set role anon'); try { return await db.query(sql) } finally { await db.exec('reset role') } };
await fails(asAnon('select * from ad_rewards'), 'the API roles cannot read rewards');
await fails(asAnon(`insert into ad_rewards (transaction_id, install_id, nonce) values ('fake', 'A', 'n')`), 'the API roles cannot add rewards');
await fails(asAnon(`select redeem_ad_reward('n', 'A', 3, 100)`), 'the API roles cannot redeem');
await fails(asAnon('select * from generation_reports'), 'the API roles cannot read reports');

// --- AdMob signatures ---
const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const keys = [{ keyId: 3335741209, base64: publicKey.export({ type: 'spki', format: 'der' }).toString('base64') }];
const signed = (content, keyId = 3335741209) => {
  const signature = sign('sha256', Buffer.from(content), { key: privateKey, dsaEncoding: 'der' }).toString('base64url');
  return `${content}&signature=${signature}&key_id=${keyId}`;
};
const content = 'ad_network=5450213213286189855&ad_unit=1234567890&custom_data=n1&reward_amount=1&reward_item=Reward&timestamp=1700000000000&transaction_id=abc&user_id=A';
ok(await verifyRewardCallback(signed(content), keys), "Google's signature verifies");
ok(!await verifyRewardCallback(signed(content).replace('user_id=A', 'user_id=B'), keys), 'a changed install fails');
ok(!await verifyRewardCallback(signed(content).replace('custom_data=n1', 'custom_data=n2'), keys), 'a changed nonce fails');
ok(!await verifyRewardCallback(signed(content, 1), keys), 'an unknown key fails');
ok(!await verifyRewardCallback(content, keys), 'an unsigned callback fails');
let allVerify = true;
for (let i = 0; i < 50; i++) allVerify &&= await verifyRewardCallback(signed(content + i), keys);
ok(allVerify, 'DER signatures of every length convert (50 samples)');
