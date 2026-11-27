// Serves wallpaper files (videos, stills, thumbnails, category covers) from Workers KV (free tier, zero card).
// Anyone can read; only admins with a valid HMAC-SHA256 JWT (issued by glitter-api) can upload or delete.
// Paths match the catalog rows (`videos/<id>.mp4`, `images/<id>.png`, `thumbnails/<id>.jpg`, `covers/<id>.jpg`).

const KEY = /^(videos|images|thumbnails|covers)\/[\w.-]+$/;
const IMMUTABLE = 'public, max-age=31536000, immutable';

export default {
  async fetch(request, env) {
    const key = decodeURIComponent(new URL(request.url).pathname.slice(1));
    const cors = corsHeaders(request, env);
    switch (request.method) {
      case 'GET':
      case 'HEAD':
        return serve(request, env, key);
      case 'OPTIONS':
        return new Response(null, { status: cors ? 204 : 403, headers: cors ?? {} });
      case 'PUT':
      case 'DELETE': {
        if (!cors) return new Response('Forbidden', { status: 403 });
        const response = await write(request, env, key);
        for (const [name, value] of Object.entries(cors)) response.headers.set(name, value);
        return response;
      }
      default:
        return new Response('Method not allowed', { status: 405, headers: { allow: 'GET, HEAD, PUT, DELETE, OPTIONS' } });
    }
  },
};

async function serve(request, env, key) {
  if (!KEY.test(key)) return new Response('Not found', { status: 404 });
  const rangeHeader = request.headers.get('range');
  const isHead = request.method === 'HEAD';

  // Read as stream for HEAD / full GET; buffer only when slicing a byte Range response.
  const entry = rangeHeader && !isHead
    ? await env.WALLPAPERS.getWithMetadata(key, 'arrayBuffer')
    : await env.WALLPAPERS.getWithMetadata(key, 'stream');

  if (!entry || entry.value === null) return new Response('Not found', { status: 404 });

  const meta = entry.metadata ?? {};
  const headers = new Headers();
  headers.set('content-type', meta.contentType || inferContentType(key));
  headers.set('cache-control', meta.cacheControl || IMMUTABLE);
  if (meta.etag) headers.set('etag', meta.etag);
  headers.set('accept-ranges', 'bytes');

  if (isHead) {
    if (typeof entry.value?.cancel === 'function') await entry.value.cancel();
    if (typeof meta.size === 'number') headers.set('content-length', String(meta.size));
    return new Response(null, { headers });
  }

  const ifNoneMatch = request.headers.get('if-none-match');
  if (ifNoneMatch && meta.etag && ifNoneMatch === meta.etag) {
    if (typeof entry.value?.cancel === 'function') await entry.value.cancel();
    return new Response(null, { status: 304, headers });
  }

  if (rangeHeader) {
    const buf = entry.value;
    const size = buf.byteLength;
    const span = parseRange(rangeHeader, size);
    if (!span) return new Response('Range not satisfiable', { status: 416 });
    const slice = buf.slice(span.offset, span.offset + span.length);
    headers.set('content-range', `bytes ${span.offset}-${span.offset + span.length - 1}/${size}`);
    headers.set('content-length', String(span.length));
    return new Response(slice, { status: 206, headers });
  }

  if (typeof meta.size === 'number') headers.set('content-length', String(meta.size));
  return new Response(entry.value, { headers });
}

/** Parses an HTTP Range header (`bytes=start-end`, `bytes=start-`, or `bytes=-suffix`) into `{ offset, length }`. */
export function parseRange(header, size) {
  const match = /^bytes=(\d*)-(\d*)$/i.exec(header.trim());
  if (!match || size <= 0) return null;
  const [, startStr, endStr] = match;
  if (!startStr && !endStr) return null;
  if (!startStr) {
    const suffix = Number(endStr);
    if (!Number.isFinite(suffix) || suffix <= 0) return null;
    const length = Math.min(suffix, size);
    return { offset: size - length, length };
  }
  const offset = Number(startStr);
  if (!Number.isFinite(offset) || offset >= size) return null;
  const end = endStr ? Math.min(Number(endStr), size - 1) : size - 1;
  if (end < offset) return null;
  return { offset, length: end - offset + 1 };
}

function inferContentType(key) {
  if (key.endsWith('.mp4')) return 'video/mp4';
  if (key.endsWith('.mov')) return 'video/quicktime';
  if (key.endsWith('.png')) return 'image/png';
  if (key.endsWith('.jpg') || key.endsWith('.jpeg')) return 'image/jpeg';
  return 'application/octet-stream';
}

async function write(request, env, key) {
  if (!KEY.test(key)) return new Response('Bad path', { status: 400 });
  if (!(await isAdmin(request, env))) return new Response('Admins only', { status: 403 });
  if (request.method === 'DELETE') {
    await env.WALLPAPERS.delete(key);
    return new Response(null, { status: 204 });
  }
  // Files are cached as immutable, so one is never replaced: the admin site uploads under a new path instead.
  const existing = await env.WALLPAPERS.getWithMetadata(key, 'stream');
  if (existing?.value) {
    if (typeof existing.value.cancel === 'function') await existing.value.cancel();
    return new Response('Already exists', { status: 409 });
  }
  const body = await request.arrayBuffer();
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', body));
  const etag = `"${Array.from(digest.slice(0, 8), (b) => b.toString(16).padStart(2, '0')).join('')}"`;
  await env.WALLPAPERS.put(key, body, {
    metadata: {
      contentType: request.headers.get('content-type') ?? inferContentType(key),
      cacheControl: IMMUTABLE,
      size: body.byteLength,
      etag,
    },
  });
  return new Response(null, { status: 201 });
}

/** Verifies the HMAC-SHA256 Bearer JWT issued by glitter-api's /admin/login endpoint. */
export async function isAdmin(request, env) {
  const secret = env.ADMIN_JWT_SECRET;
  if (!secret) return false;
  const authorization = request.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ')) return false;
  const token = authorization.slice(7).trim();
  const parts = token.split('.');
  if (parts.length !== 3) return false;
  const [headerPart, payloadPart, signaturePart] = parts;

  try {
    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    const valid = await crypto.subtle.verify(
      'HMAC',
      key,
      fromBase64Url(signaturePart),
      new TextEncoder().encode(`${headerPart}.${payloadPart}`),
    );
    if (!valid) return false;
    const header = JSON.parse(new TextDecoder().decode(fromBase64Url(headerPart)));
    if (header.alg !== 'HS256') return false;
    const payload = JSON.parse(new TextDecoder().decode(fromBase64Url(payloadPart)));
    const now = Math.floor(Date.now() / 1000);
    return payload.role === 'admin' && typeof payload.exp === 'number' && payload.exp > now;
  } catch {
    return false;
  }
}

function fromBase64Url(text) {
  const padded = text.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (text.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

/** CORS for the admin site only; null for any other origin. */
function corsHeaders(request, env) {
  const origin = request.headers.get('origin');
  const allowed = (env.ADMIN_ORIGINS ?? '').split(',').map((s) => s.trim()).filter(Boolean);
  if (!origin || !allowed.includes(origin)) return null;
  return {
    'access-control-allow-origin': origin,
    'access-control-allow-methods': 'PUT, DELETE',
    'access-control-allow-headers': 'authorization, content-type',
    'access-control-max-age': '86400',
    vary: 'origin',
  };
}
