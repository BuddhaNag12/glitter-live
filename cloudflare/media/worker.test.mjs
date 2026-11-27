// Checks the KV-backed media Worker against a stand-in KV namespace and HMAC-SHA256 admin JWTs.
// Run: node cloudflare/media/worker.test.mjs
import assert from 'node:assert/strict';
import worker, { parseRange } from './worker.js';

const SECRET = 'test-admin-jwt-secret';
const env = {
  ADMIN_JWT_SECRET: SECRET,
  ADMIN_ORIGINS: 'https://admin.test',
  WALLPAPERS: fakeKV({
    'videos/a.mp4': {
      bytes: '0123456789',
      metadata: { contentType: 'video/mp4', cacheControl: 'public, max-age=31536000, immutable', size: 10, etag: '"etag-a"' },
    },
  }),
};

async function signJwt(payload, secret = SECRET) {
  const toB64Url = (bytes) => Buffer.from(bytes).toString('base64url');
  const header = toB64Url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = toB64Url(JSON.stringify(payload));
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${header}.${body}`));
  return `${header}.${body}.${toB64Url(new Uint8Array(sig))}`;
}

const now = Math.floor(Date.now() / 1000);
const adminToken = await signJwt({ sub: 'admin@test', role: 'admin', exp: now + 3600 });
const userToken = await signJwt({ sub: 'user@test', role: 'user', exp: now + 3600 });
const expiredToken = await signJwt({ sub: 'admin@test', role: 'admin', exp: now - 10 });
const wrongSecretToken = await signJwt({ sub: 'admin@test', role: 'admin', exp: now + 3600 }, 'wrong');

const call = (method, path, headers = {}, body) =>
  worker.fetch(new Request(`https://media.test/${path}`, { method, headers, body, duplex: 'half' }), env);

// Reading
let response = await call('GET', 'videos/a.mp4');
assert.equal(response.status, 200);
assert.equal(await response.text(), '0123456789');
assert.equal(response.headers.get('content-type'), 'video/mp4');
assert.equal(response.headers.get('cache-control'), 'public, max-age=31536000, immutable');
assert.equal(response.headers.get('etag'), '"etag-a"');

response = await call('GET', 'videos/a.mp4', { 'if-none-match': '"etag-a"' });
assert.equal(response.status, 304);

response = await call('GET', 'videos/a.mp4', { range: 'bytes=2-5' });
assert.equal(response.status, 206, 'AVPlayer streams with byte ranges');
assert.equal(response.headers.get('content-range'), 'bytes 2-5/10');
assert.equal(await response.text(), '2345');

response = await call('GET', 'videos/a.mp4', { range: 'bytes=99-100' });
assert.equal(response.status, 416);

response = await call('HEAD', 'videos/a.mp4');
assert.equal(response.status, 200);
assert.equal(response.headers.get('content-length'), '10');

assert.equal((await call('GET', 'videos/missing.mp4')).status, 404);
assert.equal((await call('GET', 'secret/x')).status, 404, 'only catalog folders are served');

assert.deepEqual(parseRange('bytes=-4', 10), { offset: 6, length: 4 });
assert.deepEqual(parseRange('bytes=8-', 10), { offset: 8, length: 2 });
assert.deepEqual(parseRange('bytes=0-99', 10), { offset: 0, length: 10 });
assert.equal(parseRange('bytes=12-20', 10), null);

// Writing & Auth
const admin = { origin: 'https://admin.test', authorization: `Bearer ${adminToken}`, 'content-type': 'image/jpeg' };
assert.equal((await call('PUT', 'thumbnails/b.jpg', { ...admin, origin: 'https://evil.test' }, 'x')).status, 403, 'other sites');
assert.equal((await call('PUT', 'thumbnails/b.jpg', { ...admin, authorization: `Bearer ${userToken}` }, 'x')).status, 403, 'non-admins');
assert.equal((await call('PUT', 'thumbnails/b.jpg', { ...admin, authorization: `Bearer ${expiredToken}` }, 'x')).status, 403, 'expired jwt');
assert.equal((await call('PUT', 'thumbnails/b.jpg', { ...admin, authorization: `Bearer ${wrongSecretToken}` }, 'x')).status, 403, 'tampered jwt');
assert.equal((await call('PUT', '../b.jpg', admin, 'x')).status, 400);

response = await call('PUT', 'thumbnails/b.jpg', admin, 'jpeg');
assert.equal(response.status, 201);
assert.equal(response.headers.get('access-control-allow-origin'), 'https://admin.test');
assert.equal(await (await call('GET', 'thumbnails/b.jpg')).text(), 'jpeg');
assert.equal((await call('PUT', 'thumbnails/b.jpg', admin, 'other')).status, 409, 'files are never replaced');

assert.equal((await call('DELETE', 'thumbnails/b.jpg', { ...admin, authorization: `Bearer ${userToken}` })).status, 403);
assert.equal((await call('DELETE', 'thumbnails/b.jpg', admin)).status, 204);
assert.equal((await call('GET', 'thumbnails/b.jpg')).status, 404);

assert.equal((await call('OPTIONS', 'thumbnails/b.jpg', { origin: 'https://admin.test' })).status, 204);
console.log('media worker (KV): all checks passed');

/** Stand-in KVNamespace implementing getWithMetadata, put, delete. */
function fakeKV(initial) {
  const store = new Map(
    Object.entries(initial).map(([k, v]) => [
      k,
      { bytes: Buffer.from(v.bytes), metadata: v.metadata },
    ]),
  );
  return {
    async getWithMetadata(key, type) {
      const item = store.get(key);
      if (!item) return { value: null, metadata: null };
      if (type === 'stream') {
        return { value: new Response(item.bytes).body, metadata: item.metadata };
      }
      if (type === 'arrayBuffer') {
        return {
          value: item.bytes.buffer.slice(item.bytes.byteOffset, item.bytes.byteOffset + item.bytes.byteLength),
          metadata: item.metadata,
        };
      }
      return { value: item.bytes.toString('utf8'), metadata: item.metadata };
    },
    async put(key, body, { metadata }) {
      const bytes = Buffer.from(body);
      store.set(key, { bytes, metadata });
    },
    async delete(key) {
      store.delete(key);
    },
  };
}
