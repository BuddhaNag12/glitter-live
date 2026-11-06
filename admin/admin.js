// Glitter Live catalog admin. Plain JS, no build step.
// Only the publishable key ships here; writes are allowed by row level security for users in public.admins.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.4';

const PROJECT_URL = 'https://jusrioirjfpaocgmsbbv.supabase.co';
const PUBLISHABLE_KEY = 'sb_publishable_H8JSLO_Abl7S2ocPsk1LSQ_OT3w-Xny';
const BUCKET = 'wallpapers';
const MAX_SECONDS = 5; // The Lock Screen plays Live Photos up to 5 s; the database enforces it too.
const THUMBNAIL_WIDTH = 540; // Matches scripts/wallpaper-tool.swift.

const supabase = createClient(PROJECT_URL, PUBLISHABLE_KEY);
const $ = (id) => document.getElementById(id);
let wallpapers = [];

// Session

supabase.auth.onAuthStateChange((_event, session) => {
  $('login').hidden = !!session;
  $('app').hidden = !session;
  // supabase-js deadlocks if its own calls run inside this callback.
  if (session) setTimeout(loadList);
});

$('login').addEventListener('submit', async (event) => {
  event.preventDefault();
  setStatus('login-status', 'Signing in…');
  const { error } = await supabase.auth.signInWithPassword({ email: $('email').value, password: $('password').value });
  setStatus('login-status', error ? error.message : '', !!error);
});

$('sign-out').addEventListener('click', () => supabase.auth.signOut());

// Upload

$('file').addEventListener('change', async () => {
  const file = $('file').files[0];
  $('preview').hidden = true;
  setStatus('upload-status', '');
  if (!file) return;
  try {
    const media = await readMedia(file);
    $('preview').src = URL.createObjectURL(media.thumbnail);
    $('preview').hidden = false;
    setStatus('upload-status', media.kind === 'live'
      ? `Live wallpaper, ${media.duration.toFixed(1)} s, ${media.width}×${media.height}`
      : `Still wallpaper, ${media.width}×${media.height}`);
  } catch (error) {
    setStatus('upload-status', error.message, true);
  }
});

$('upload').addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = $('upload-button');
  button.disabled = true;
  try {
    const file = $('file').files[0];
    const media = await readMedia(file);
    const id = crypto.randomUUID();
    const extension = file.name.split('.').pop().toLowerCase();
    const mediaPath = `${media.kind === 'live' ? 'videos' : 'images'}/${id}.${extension}`;
    const thumbnailPath = `thumbnails/${id}.jpg`;

    // Media, then thumbnail, then the row: the app never sees a row whose files are missing.
    setStatus('upload-status', 'Uploading media…');
    await upload(mediaPath, file, file.type);
    try {
      setStatus('upload-status', 'Uploading thumbnail…');
      await upload(thumbnailPath, media.thumbnail, 'image/jpeg');
      setStatus('upload-status', 'Adding to the catalog…');
      const { error } = await supabase.from('wallpapers').insert({
        id,
        kind: media.kind,
        title: $('title').value.trim(),
        category: $('category').value.trim(),
        video_path: media.kind === 'live' ? mediaPath : null,
        image_path: media.kind === 'still' ? mediaPath : null,
        thumbnail_path: thumbnailPath,
        duration_seconds: media.kind === 'live' ? media.duration : null,
        width: media.width,
        height: media.height,
        creator_name: $('creator').value.trim() || null,
        creator_url: $('creator-url').value.trim() || null,
        is_published: $('published').checked,
        is_featured: $('featured').checked,
      });
      if (error) throw error;
    } catch (error) {
      await supabase.storage.from(BUCKET).remove([mediaPath, thumbnailPath]);
      throw error;
    }
    $('upload').reset();
    $('preview').hidden = true;
    setStatus('upload-status', 'Uploaded.');
    await loadList();
  } catch (error) {
    setStatus('upload-status', error.message, true);
  } finally {
    button.disabled = false;
  }
});

async function upload(path, body, contentType) {
  // Files are cached as immutable, so a wallpaper's media is never replaced: delete and re-upload instead.
  const { error } = await supabase.storage.from(BUCKET).upload(path, body, { contentType, cacheControl: '31536000', upsert: false });
  if (error) throw error;
}

/** Reads the file's size (and length, for video) and draws a 540 px JPEG thumbnail. */
async function readMedia(file) {
  if (!file) throw new Error('Choose a file.');
  if (file.type.startsWith('image/')) {
    const bitmap = await createImageBitmap(file);
    return { kind: 'still', width: bitmap.width, height: bitmap.height, thumbnail: await thumbnail(bitmap, bitmap.width, bitmap.height) };
  }
  if (!file.type.startsWith('video/')) throw new Error('Choose an MP4 or MOV video, or a JPEG or PNG image.');

  const video = document.createElement('video');
  video.muted = true;
  video.playsInline = true;
  video.preload = 'auto';
  video.src = URL.createObjectURL(file);
  try {
    await once(video, 'loadedmetadata');
    const duration = video.duration;
    if (!Number.isFinite(duration) || !video.videoWidth) throw new Error("This browser can't read the video. Try Safari.");
    if (duration > MAX_SECONDS) throw new Error(`The video is ${duration.toFixed(1)} s. Trim it to ${MAX_SECONDS} s or less.`);
    video.currentTime = duration / 2;
    await once(video, 'seeked');
    return {
      kind: 'live', duration: Math.round(duration * 100) / 100, width: video.videoWidth, height: video.videoHeight,
      thumbnail: await thumbnail(video, video.videoWidth, video.videoHeight),
    };
  } finally {
    URL.revokeObjectURL(video.src);
  }
}

function thumbnail(source, width, height) {
  const canvas = document.createElement('canvas');
  canvas.width = THUMBNAIL_WIDTH;
  canvas.height = Math.round(height * THUMBNAIL_WIDTH / width);
  canvas.getContext('2d').drawImage(source, 0, 0, canvas.width, canvas.height);
  return new Promise((resolve, reject) => canvas.toBlob((blob) => blob ? resolve(blob) : reject(new Error('Thumbnail failed.')), 'image/jpeg', 0.85));
}

function once(target, event) {
  return new Promise((resolve, reject) => {
    target.addEventListener(event, resolve, { once: true });
    target.addEventListener('error', () => reject(new Error("This browser can't read the file. Try Safari.")), { once: true });
  });
}

// List

async function loadList() {
  const { data, error } = await supabase.from('wallpapers').select('*').order('sort_order').order('created_at', { ascending: false });
  if (error) return setStatus('list-status', error.message, true);
  wallpapers = data;
  setStatus('list-status', data.length ? '' : 'No wallpapers yet.');
  $('categories').replaceChildren(...[...new Set(data.map((w) => w.category))].map((value) => Object.assign(document.createElement('option'), { value })));
  $('list').replaceChildren(...data.map(row));
}

function row(wallpaper) {
  const item = el('li', { className: 'item', draggable: true });
  item.dataset.id = wallpaper.id;
  const meta = el('div', { className: 'meta' });
  meta.append(el('span', { className: 'badge', textContent: wallpaper.kind.toUpperCase() }),
    wallpaper.kind === 'live' ? `${wallpaper.duration_seconds} s · ` : '', `${wallpaper.width}×${wallpaper.height}`);
  const fields = el('div', { className: 'fields' });
  fields.append(
    field(wallpaper, 'title', 'Title'),
    field(wallpaper, 'category', 'Category', 'categories'),
    field(wallpaper, 'creator_name', 'Creator'),
    field(wallpaper, 'creator_url', 'Creator link'),
  );
  const details = el('div');
  details.append(fields, meta);
  const toggles = el('div', { className: 'toggles' });
  const remove = el('button', { className: 'danger', type: 'button', textContent: 'Delete' });
  remove.addEventListener('click', () => deleteWallpaper(wallpaper));
  toggles.append(toggle(wallpaper, 'is_published', 'Published'), toggle(wallpaper, 'is_featured', 'Featured'), remove);
  item.append(
    el('div', { className: 'handle', textContent: '⋮⋮', title: 'Drag to reorder' }),
    el('img', { src: `${PROJECT_URL}/storage/v1/object/public/${BUCKET}/${wallpaper.thumbnail_path}`, alt: '', loading: 'lazy' }),
    details, toggles,
  );
  return item;
}

function field(wallpaper, key, label, list) {
  const input = el('input', { type: 'text', value: wallpaper[key] ?? '', placeholder: label, title: label });
  input.setAttribute('aria-label', label);
  if (list) input.setAttribute('list', list);
  input.addEventListener('change', () => {
    const value = input.value.trim();
    save(wallpaper, { [key]: value || (key === 'title' || key === 'category' ? wallpaper[key] : null) }, () => { input.value = wallpaper[key] ?? ''; });
  });
  return input;
}

function toggle(wallpaper, key, label) {
  const input = el('input', { type: 'checkbox', checked: wallpaper[key] });
  input.addEventListener('change', () => save(wallpaper, { [key]: input.checked }, () => { input.checked = wallpaper[key]; }));
  const wrapper = el('label', { className: 'check' });
  wrapper.append(input, label);
  return wrapper;
}

async function save(wallpaper, changes, revert) {
  const { error } = await supabase.from('wallpapers').update(changes).eq('id', wallpaper.id);
  if (error) {
    revert();
    return setStatus('list-status', error.message, true);
  }
  Object.assign(wallpaper, changes);
  setStatus('list-status', `Saved “${wallpaper.title}”.`);
}

async function deleteWallpaper(wallpaper) {
  if (!confirm(`Delete “${wallpaper.title}”? It disappears from Explore for everyone.`)) return;
  // The row first, so the app stops listing it before its files go.
  const { error } = await supabase.from('wallpapers').delete().eq('id', wallpaper.id);
  if (error) return setStatus('list-status', error.message, true);
  const { error: filesError } = await supabase.storage.from(BUCKET)
    .remove([wallpaper.video_path ?? wallpaper.image_path, wallpaper.thumbnail_path]);
  setStatus('list-status', filesError ? `Deleted, but its files remain: ${filesError.message}` : `Deleted “${wallpaper.title}”.`, !!filesError);
  await loadList();
}

// Drag to reorder

let dragged;
$('list').addEventListener('dragstart', (event) => {
  dragged = event.target.closest('li.item');
  dragged?.classList.add('dragging');
});
$('list').addEventListener('dragover', (event) => {
  const target = event.target.closest('li.item');
  if (!dragged || !target || target === dragged) return;
  event.preventDefault();
  document.querySelectorAll('li.over').forEach((li) => li.classList.remove('over'));
  target.classList.add('over');
});
$('list').addEventListener('dragend', () => {
  dragged?.classList.remove('dragging');
  document.querySelectorAll('li.over').forEach((li) => li.classList.remove('over'));
  dragged = undefined;
});
$('list').addEventListener('drop', async (event) => {
  event.preventDefault();
  const target = event.target.closest('li.item');
  if (!dragged || !target || target === dragged) return;
  const items = [...$('list').children];
  if (items.indexOf(dragged) < items.indexOf(target)) target.after(dragged); else target.before(dragged);
  const order = [...$('list').children].map((li) => li.dataset.id);
  const moved = order
    .map((id, index) => ({ wallpaper: wallpapers.find((w) => w.id === id), sort_order: index * 10 }))
    .filter(({ wallpaper, sort_order }) => wallpaper.sort_order !== sort_order);
  const results = await Promise.all(moved.map(({ wallpaper, sort_order }) =>
    supabase.from('wallpapers').update({ sort_order }).eq('id', wallpaper.id)));
  const failed = results.find((result) => result.error);
  setStatus('list-status', failed ? failed.error.message : `Reordered ${moved.length} wallpaper${moved.length === 1 ? '' : 's'}.`, !!failed);
  await loadList();
});

// Helpers

function el(tag, properties = {}) {
  return Object.assign(document.createElement(tag), properties);
}

function setStatus(id, message, isError = false) {
  $(id).textContent = message;
  $(id).classList.toggle('error', isError);
}
