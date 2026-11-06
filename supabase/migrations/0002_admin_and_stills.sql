-- Still wallpapers, a featured flag, and an admin login for the upload site.
--
-- The shipped 1.0 app reads `wallpapers` directly and fails to decode the whole list if any row has no
-- `video_path`, so it must only ever see live rows. 1.1 and later read the `catalog` view instead.

alter table public.wallpapers
    add column if not exists kind text not null default 'live' check (kind in ('live', 'still')),
    add column if not exists image_path text,
    add column if not exists is_featured boolean not null default false,
    alter column video_path drop not null,
    alter column duration_seconds drop not null;

alter table public.wallpapers
    add constraint wallpapers_media_check check (
        (kind = 'live' and video_path like 'videos/%' and duration_seconds is not null and image_path is null)
        or (kind = 'still' and image_path like 'images/%' and video_path is null and duration_seconds is null)
    ),
    add constraint wallpapers_thumbnail_check check (thumbnail_path like 'thumbnails/%'),
    add constraint wallpapers_title_check check (char_length(btrim(title)) between 1 and 80);

-- 1.0 reads this table with the publishable key: live rows only.
drop policy if exists "Published wallpapers are readable by everyone" on public.wallpapers;
create policy "Published live wallpapers are readable by everyone"
    on public.wallpapers
    for select
    to anon, authenticated
    using (is_published and kind = 'live');

-- What 1.1 reads. It runs with its owner's rights on purpose (so stills get past the 1.0 policy above)
-- and filters published rows itself. A change that would break an app's decoder gets `catalog_v2`.
create or replace view public.catalog as
    select id, kind, title, category, video_path, image_path, thumbnail_path, duration_seconds,
           width, height, creator_name, creator_url, is_featured, sort_order, created_at
    from public.wallpapers
    where is_published;

-- Supabase grants everything on new relations to the API roles, and a simple view is writable,
-- which with owner rights would bypass row level security. Read only.
revoke all on public.catalog from anon, authenticated;
grant select on public.catalog to anon, authenticated;

-- The admin allowlist. Row level security with no policies, so it can't be read through the API.
create table if not exists public.admins (
    user_id uuid primary key references auth.users (id) on delete cascade
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (select 1 from public.admins where user_id = auth.uid());
$$;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

drop policy if exists "Admins manage wallpapers" on public.wallpapers;
create policy "Admins manage wallpapers"
    on public.wallpapers
    for all
    to authenticated
    using ((select public.is_admin()))
    with check ((select public.is_admin()));

drop policy if exists "Admins manage wallpaper files" on storage.objects;
create policy "Admins manage wallpaper files"
    on storage.objects
    for all
    to authenticated
    using (bucket_id = 'wallpapers' and (select public.is_admin()))
    with check (bucket_id = 'wallpapers' and (select public.is_admin()));

update storage.buckets
set file_size_limit = 50 * 1024 * 1024,
    allowed_mime_types = array['video/mp4', 'video/quicktime', 'image/jpeg', 'image/png']
where id = 'wallpapers';
