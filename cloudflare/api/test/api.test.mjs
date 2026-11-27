// Integration tests for glitter-api against real local Miniflare D1 and the bundled Worker.
// Run: cd cloudflare/api && npm test
import assert from 'node:assert/strict';
import { generateKeyPairSync, pbkdf2Sync, randomBytes, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';
import { getPlatformProxy } from 'wrangler';
import worker from '../.wrangler/test-dist/index.js';

const ADMIN_EMAIL = 'admin@glitter.test';
const ADMIN_PASSWORD = 'correct-horse-battery-staple';
const ADMIN_ORIGIN = 'https://glitter-live-admin.vercel.app';
const JWT_SECRET = 'test-jwt-secret-for-local-suite';

function hashPassword(password) {
  const iterations = 100_000;
  const salt = randomBytes(16);
  const derived = pbkdf2Sync(password, salt, iterations, 32, 'sha256');
  return `pbkdf2_sha256$${iterations}$${salt.toString('hex')}$${derived.toString('hex')}`;
}

let proxy;
let env;
let aiResponder = async (model, input) => {
  if (model.includes('llama-guard')) return { response: 'safe' };
  if (model.includes('flux')) return { image: Buffer.from('fake-jpeg-bytes').toString('base64') };
  if (model.includes('vision')) return { response: 'SAFE' };
  throw new Error(`Unexpected model: ${model}`);
};

const call = (path, init = {}) =>
  worker.fetch(new Request(`https://api.test${path}`, init), env);

before(async () => {
  proxy = await getPlatformProxy({ configPath: 'wrangler.jsonc', persist: false, remoteBindings: false });
  const schema = readFileSync(new URL('../migrations/0001_init.sql', import.meta.url), 'utf8');
  for (const stmt of schema.split(';').map((s) => s.trim()).filter(Boolean)) {
    await proxy.env.DB.prepare(stmt).run();
  }
  env = {
    ...proxy.env,
    ADMIN_EMAIL,
    ADMIN_PASSWORD_HASH: hashPassword(ADMIN_PASSWORD),
    ADMIN_JWT_SECRET: JWT_SECRET,
    ADMOB_REWARDED_AD_UNIT: '1234567890',
    DAILY_GENERATIONS_PER_INSTALL: '3',
    DAILY_GENERATIONS_TOTAL: '10',
    REQUIRE_AD_REWARD: 'true',
    ALLOW_VIDEO: 'false',
    AI: {
      run: (model, input) => aiResponder(model, input),
    },
  };
});

after(async () => {
  await proxy?.dispose();
});

test('admin login rejects bad credentials and issues working JWT', async () => {
  const bad = await call('/admin/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin: ADMIN_ORIGIN },
    body: JSON.stringify({ email: ADMIN_EMAIL, password: 'wrong-password' }),
  });
  assert.equal(bad.status, 401);
  assert.equal(bad.headers.get('access-control-allow-origin'), ADMIN_ORIGIN);

  const unauth = await call('/admin/wallpapers');
  assert.equal(unauth.status, 401);

  const good = await call('/admin/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin: ADMIN_ORIGIN },
    body: JSON.stringify({ email: ADMIN_EMAIL, password: ADMIN_PASSWORD }),
  });
  assert.equal(good.status, 200);
  const { token, email } = await good.json();
  assert.equal(email, ADMIN_EMAIL);
  assert.ok(token.split('.').length === 3);

  const me = await call('/admin/me', { headers: { authorization: `Bearer ${token}` } });
  assert.equal(me.status, 200);
  assert.deepEqual(await me.json(), { ok: true, email: ADMIN_EMAIL });
});

test('catalog CRUD, unpublished hiding, schema checks, and category covers', async () => {
  const loginRes = await call('/admin/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: ADMIN_EMAIL, password: ADMIN_PASSWORD }),
  });
  const { token } = await loginRes.json();
  const auth = { authorization: `Bearer ${token}`, 'content-type': 'application/json', origin: ADMIN_ORIGIN };

  // Create live, still, and unpublished draft
  const r1 = await call('/admin/wallpapers', {
    method: 'POST',
    headers: auth,
    body: JSON.stringify({
      kind: 'live',
      title: 'Glacier',
      category: 'Glitter Originals',
      video_path: 'videos/g1.mp4',
      thumbnail_path: 'thumbnails/g1.jpg',
      duration_seconds: 4,
      width: 1080,
      height: 1920,
      is_published: true,
      is_category_cover: true,
      sort_order: 20,
    }),
  });
  assert.equal(r1.status, 201);
  const w1 = await r1.json();

  const r2 = await call('/admin/wallpapers', {
    method: 'POST',
    headers: auth,
    body: JSON.stringify({
      kind: 'still',
      title: 'Moonlit Bay',
      category: 'Glitter Originals',
      image_path: 'images/m1.png',
      thumbnail_path: 'thumbnails/m1.jpg',
      width: 1179,
      height: 2556,
      is_published: true,
      is_featured: true,
      sort_order: 10,
    }),
  });
  assert.equal(r2.status, 201);
  const w2 = await r2.json();

  const rDraft = await call('/admin/wallpapers', {
    method: 'POST',
    headers: auth,
    body: JSON.stringify({
      kind: 'live',
      title: 'Draft Hidden',
      category: 'Glitter Originals',
      video_path: 'videos/draft.mp4',
      thumbnail_path: 'thumbnails/draft.jpg',
      duration_seconds: 3,
      width: 1080,
      height: 1920,
      is_published: false,
      sort_order: 1,
    }),
  });
  assert.equal(rDraft.status, 201);

  // Public catalog sees only published rows ordered by sort_order ASC, with booleans
  const pubRes = await call('/catalog');
  assert.equal(pubRes.status, 200);
  const pub = await pubRes.json();
  assert.equal(pub.length, 2);
  assert.equal(pub[0].id, w2.id);
  assert.equal(pub[0].is_featured, true);
  assert.equal(pub[0].is_category_cover, false);
  assert.equal(pub[1].id, w1.id);
  assert.equal(pub[1].is_category_cover, true);

  // Admin sees all 3 including draft
  const allRes = await call('/admin/wallpapers', { headers: auth });
  assert.equal((await allRes.json()).length, 3);

  // Constraint checks: still with video, live without duration, blank title
  assert.equal(
    (await call('/admin/wallpapers', {
      method: 'POST',
      headers: auth,
      body: JSON.stringify({
        kind: 'still',
        title: 'Bad Still',
        category: 'Ocean',
        video_path: 'videos/x.mp4',
        image_path: 'images/x.png',
        thumbnail_path: 'thumbnails/x.jpg',
        width: 100,
        height: 100,
      }),
    })).status,
    400,
  );
  assert.equal(
    (await call('/admin/wallpapers', {
      method: 'POST',
      headers: auth,
      body: JSON.stringify({
        kind: 'live',
        title: '   ',
        category: 'Ocean',
        video_path: 'videos/x.mp4',
        thumbnail_path: 'thumbnails/x.jpg',
        duration_seconds: 3,
        width: 100,
        height: 100,
      }),
    })).status,
    400,
  );

  // Swapping category cover atomically via PATCH clears w1 and sets w2
  const patchCover = await call(`/admin/wallpapers/${w2.id}`, {
    method: 'PATCH',
    headers: auth,
    body: JSON.stringify({ is_category_cover: true }),
  });
  assert.equal(patchCover.status, 200);
  const afterSwap = await (await call('/catalog')).json();
  assert.equal(afterSwap.find((x) => x.id === w2.id).is_category_cover, true);
  assert.equal(afterSwap.find((x) => x.id === w1.id).is_category_cover, false);

  // Category cover images CRUD
  assert.equal(
    (await call('/admin/category-covers/Ocean', {
      method: 'PUT',
      headers: auth,
      body: JSON.stringify({ image_path: 'videos/wrong.mp4' }),
    })).status,
    400,
  );
  assert.equal(
    (await call('/admin/category-covers/Ocean', {
      method: 'PUT',
      headers: auth,
      body: JSON.stringify({ image_path: 'covers/ocean.jpg' }),
    })).status,
    200,
  );
  assert.deepEqual(await (await call('/category-covers')).json(), [
    { category: 'Ocean', image_path: 'covers/ocean.jpg' },
  ]);
  assert.equal((await call('/admin/category-covers/Ocean', { method: 'DELETE', headers: auth })).status, 200);
  assert.deepEqual(await (await call('/category-covers')).json(), []);

  // Delete draft
  assert.equal((await call(`/admin/wallpapers/${(await rDraft.json()).id}`, { method: 'DELETE', headers: auth })).status, 200);
});

test('AdMob SSV signature verification, reward redemption limits, refunds, and reports', async () => {
  // Generate ECDSA P-256 test keypair and mock Google's verifier-keys fetch
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const keys = [{ keyId: 3335741209, base64: publicKey.export({ type: 'spki', format: 'der' }).toString('base64') }];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, ...rest) => {
    if (String(url) === 'https://www.gstatic.com/admob/reward/verifier-keys.json') {
      return Response.json({ keys });
    }
    return originalFetch(url, ...rest);
  };

  try {
    const signQuery = (content, keyId = 3335741209) => {
      const sig = sign('sha256', Buffer.from(content), { key: privateKey, dsaEncoding: 'der' }).toString('base64url');
      return `${content}&signature=${sig}&key_id=${keyId}`;
    };

    const q1 = signQuery(
      'ad_network=5450213213286189855&ad_unit=1234567890&custom_data=nonce-1&reward_amount=1&reward_item=Reward&timestamp=1700000000000&transaction_id=tx-1&user_id=install-A',
    );
    // Unsigned or tampered fails
    assert.equal((await call('/ad-reward?custom_data=n&user_id=A&transaction_id=t')).status, 400);
    assert.equal((await call(`/ad-reward?${q1.replace('user_id=install-A', 'user_id=install-B')}`)).status, 400);
    // Verify URL test (no custom_data) returns 200 OK
    assert.equal((await call('/ad-reward')).status, 200);
    // Valid callback records reward, and duplicate retry is idempotent
    assert.equal((await call(`/ad-reward?${q1}`)).status, 200);
    assert.equal((await call(`/ad-reward?${q1}`)).status, 200);

    // Generation succeeds with valid reward
    const gen1 = await call('/generate', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action: 'image', prompt: 'neon ocean waves', install: 'install-A', reward: 'nonce-1' }),
    });
    assert.equal(gen1.status, 200);
    const body1 = await gen1.json();
    assert.equal(Buffer.from(body1.image, 'base64').toString('utf8'), 'fake-jpeg-bytes');

    // AI failure refunds reward so nonce-2 can be retried after failure
    const q2 = signQuery(
      'ad_network=5450213213286189855&ad_unit=1234567890&custom_data=nonce-2&reward_amount=1&reward_item=Reward&timestamp=1700000000001&transaction_id=tx-2&user_id=install-A',
    );
    assert.equal((await call(`/ad-reward?${q2}`)).status, 200);

    const prevAi = aiResponder;
    aiResponder = async (model) => {
      if (model.includes('llama-guard')) return { response: 'safe' };
      throw new Error('transient AI outage');
    };
    const failedGen = await call('/generate', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action: 'image', prompt: 'sunset', install: 'install-A', reward: 'nonce-2' }),
    });
    assert.equal(failedGen.status, 502);

    aiResponder = prevAi;
    const retriedGen = await call('/generate', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action: 'image', prompt: 'sunset', install: 'install-A', reward: 'nonce-2' }),
    });
    assert.equal(retriedGen.status, 200, 'refunded ad reward can be spent again');

    // 3rd generation succeeds; 4th hits daily_limit (429)
    const q3 = signQuery(
      'ad_network=5450213213286189855&ad_unit=1234567890&custom_data=nonce-3&reward_amount=1&reward_item=Reward&timestamp=1700000000002&transaction_id=tx-3&user_id=install-A',
    );
    const q4 = signQuery(
      'ad_network=5450213213286189855&ad_unit=1234567890&custom_data=nonce-4&reward_amount=1&reward_item=Reward&timestamp=1700000000003&transaction_id=tx-4&user_id=install-A',
    );
    await call(`/ad-reward?${q3}`);
    await call(`/ad-reward?${q4}`);
    assert.equal(
      (await call('/generate', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ action: 'image', prompt: 'forest', install: 'install-A', reward: 'nonce-3' }),
      })).status,
      200,
    );
    assert.equal(
      (await call('/generate', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ action: 'image', prompt: 'stars', install: 'install-A', reward: 'nonce-4' }),
      })).status,
      429,
    );

    // Unsafe prompt rejected before redeeming
    aiResponder = async () => ({ response: 'unsafe\nS1' });
    assert.equal(
      (await call('/generate', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ action: 'image', prompt: 'bad prompt', install: 'install-B', reward: 'unused' }),
      })).status,
      400,
    );
    aiResponder = prevAi;

    // Report endpoint
    assert.equal(
      (await call('/generate', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ action: 'report', prompt: 'a red fox', install: 'install-A', reason: 'spam' }),
      })).status,
      400,
    );
    const reportOk = await call('/generate', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action: 'report', prompt: 'a red fox', install: 'install-A', reason: 'other' }),
    });
    assert.equal(reportOk.status, 200);
    assert.deepEqual(await reportOk.json(), { reported: true });
  } finally {
    globalThis.fetch = originalFetch;
  }
});
