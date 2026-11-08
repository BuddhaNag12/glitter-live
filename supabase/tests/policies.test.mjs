// Checks the catalog's row level security against stand-ins for Supabase's roles, auth and storage.
// Run: cd supabase/tests && npm install --no-save @electric-sql/pglite@0.3.4 && node policies.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'fs';
const repo = new URL('../..', import.meta.url).pathname;
const db = new PGlite();
const ok = (c, m) => { if (!c) { console.error('FAIL', m); process.exitCode = 1 } else console.log('ok', m) };
await db.exec(`
create role anon; create role authenticated;
grant usage on schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on functions to anon, authenticated;
create schema auth; create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on function auth.uid() to anon, authenticated;
create schema storage; grant usage on schema storage to anon, authenticated;
create table storage.buckets (id text primary key, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id serial primary key, bucket_id text, name text);
alter table storage.objects enable row level security;
grant all on storage.objects to anon, authenticated; grant usage on sequence storage.objects_id_seq to authenticated;
insert into storage.buckets (id) values ('wallpapers');
`);
await db.exec(readFileSync(repo + '/supabase/migrations/0001_wallpapers.sql', 'utf8'));
for (let i = 1; i <= 6; i++) await db.query(`insert into wallpapers (title, category, video_path, thumbnail_path, duration_seconds, width, height, sort_order) values ($1, 'Glitter Originals', $2, $3, 4, 1080, 1920, $4)`, ['W' + i, `videos/${i}.mp4`, `thumbnails/${i}.jpg`, i * 10]);
await db.query(`insert into wallpapers (title, category, video_path, thumbnail_path, duration_seconds, width, height, is_published) values ('Hidden', 'X', 'videos/h.mp4', 'thumbnails/h.jpg', 3, 1080, 1920, false)`);
const SEL = 'select id,title,category,video_path,thumbnail_path,duration_seconds,width,height,creator_name,creator_url from wallpapers order by sort_order, created_at desc';
const as = async (role, sub, sql, params) => {
  await db.exec(`reset role; set request.jwt.claim.sub = '${sub ?? ''}'; set role ${role};`);
  try { return await db.query(sql, params) } finally { await db.exec('reset role') }
};
const before = JSON.stringify((await as('anon', null, SEL)).rows);
await db.exec(readFileSync(repo + '/supabase/migrations/0002_admin_and_stills.sql', 'utf8'));
ok(JSON.stringify((await as('anon', null, SEL)).rows) === before, '1.0 request unchanged after migration');
const admin = '11111111-1111-1111-1111-111111111111', other = '22222222-2222-2222-2222-222222222222';
await db.query(`insert into auth.users values ($1), ($2)`, [admin, other]);
await db.query(`insert into public.admins values ($1)`, [admin]);
const still = `insert into wallpapers (kind, title, category, image_path, thumbnail_path, width, height, is_featured) values ('still', 'Still', 'Stills', 'images/s.jpg', 'thumbnails/s.jpg', 1080, 1920, true)`;
const fails = async (p, m) => { try { await p; ok(false, m) } catch (e) { ok(true, m + ' (' + e.message.split('\n')[0] + ')') } };
await fails(as('anon', null, still), 'anon cannot insert into wallpapers');
await fails(as('authenticated', other, still), 'non-admin cannot insert');
await fails(as('anon', null, `insert into catalog (kind, title, category, image_path, thumbnail_path, width, height) values ('still','x','x','images/x.jpg','thumbnails/x.jpg',1,1)`), 'anon cannot insert into catalog view');
await fails(as('anon', null, `delete from catalog`), 'anon cannot delete through catalog view');
await as('authenticated', admin, still);
ok(true, 'admin can insert a still');
ok(JSON.stringify((await as('anon', null, SEL)).rows) === before, '1.0 request unchanged with a published still');
ok((await as('authenticated', other, SEL)).rows.length === 6, 'signed-in non-admin sees only live published');
const cat = (await as('anon', null, 'select * from catalog')).rows;
ok(cat.length === 7 && cat.some(r => r.kind === 'still' && r.is_featured), 'catalog has the 6 live + the still, not the hidden one');
ok((await as('authenticated', admin, 'select * from wallpapers')).rows.length === 8, 'admin sees unpublished rows');
await as('authenticated', admin, `update wallpapers set sort_order = 99 where title = 'W1'`);
ok((await as('anon', null, `select sort_order from catalog where title='W1'`)).rows[0].sort_order === 99, 'admin can update');
await fails(as('anon', null, 'select * from admins'), 'anon cannot read admins');
await fails(as('authenticated', admin, 'select * from admins'), 'admin cannot read admins through the API either');
await fails(db.query(`insert into wallpapers (kind, title, category, video_path, image_path, thumbnail_path, width, height) values ('still','x','x','videos/x.mp4','images/x.jpg','thumbnails/x.jpg',1,1)`), 'still with a video is rejected');
await fails(db.query(`insert into wallpapers (kind, title, category, video_path, thumbnail_path, width, height) values ('live','x','x','videos/x.mp4','thumbnails/x.jpg',1,1)`), 'live without duration is rejected');
await fails(db.query(`insert into wallpapers (title, category, video_path, thumbnail_path, duration_seconds, width, height) values (' ','x','videos/x.mp4','thumbnails/x.jpg',1,1,1)`), 'blank title is rejected');
await fails(as('authenticated', other, `insert into storage.objects (bucket_id, name) values ('wallpapers', 'videos/x.mp4')`), 'non-admin cannot upload files');
await as('authenticated', admin, `insert into storage.objects (bucket_id, name) values ('wallpapers', 'videos/x.mp4')`);
await fails(as('authenticated', admin, `insert into storage.objects (bucket_id, name) values ('other', 'x')`), 'admin cannot write other buckets');
await as('authenticated', admin, `delete from wallpapers where kind = 'still'`);
ok((await as('anon', null, 'select * from catalog')).rows.length === 6, 'admin can delete');
const before0004 = JSON.stringify((await as('anon', null, SEL)).rows);
await db.exec(readFileSync(repo + '/supabase/migrations/0004_category_covers.sql', 'utf8'));
ok(JSON.stringify((await as('anon', null, SEL)).rows) === before0004, '1.0 request unchanged after 0004');
await as('authenticated', admin, `update wallpapers set is_category_cover = true where title = 'W3'`);
ok((await as('anon', null, `select title from catalog where is_category_cover`)).rows[0]?.title === 'W3', 'admin can set a cover, and catalog shows it');
await fails(as('authenticated', admin, `update wallpapers set is_category_cover = true where title = 'W4'`), 'a second cover in the same category is rejected');
await fails(as('authenticated', other, `update wallpapers set is_category_cover = false where title = 'W3'`).then(r => { if (!r.affectedRows) throw new Error('no rows changed') }), 'non-admin cannot change covers');

