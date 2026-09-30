-- Catalog of curated live wallpapers shown in Explore.
-- Files live in the public `wallpapers` storage bucket; rows store their paths.

create table if not exists public.wallpapers (
    id uuid primary key default gen_random_uuid(),
    title text not null,
    category text not null,
    video_path text not null,
    thumbnail_path text not null,
    duration_seconds real not null check (duration_seconds > 0 and duration_seconds <= 5),
    width integer not null check (width > 0),
    height integer not null check (height > 0),
    creator_name text,
    creator_url text,
    is_published boolean not null default true,
    sort_order integer not null default 0,
    created_at timestamptz not null default now()
);

create index if not exists wallpapers_category_sort_idx
    on public.wallpapers (category, sort_order, created_at desc);

-- The app reads with the public anon key, so only published rows are visible and nothing is writable.
-- The upload script writes with the secret key, which bypasses row level security.
alter table public.wallpapers enable row level security;

drop policy if exists "Published wallpapers are readable by everyone" on public.wallpapers;
create policy "Published wallpapers are readable by everyone"
    on public.wallpapers
    for select
    to anon, authenticated
    using (is_published);
