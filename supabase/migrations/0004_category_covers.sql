-- The admin site can pick which wallpaper a category's Explore tile shows. Without a pick the tile
-- shows the category's first wallpaper, as before, and apps that don't read the column keep doing so.

alter table public.wallpapers
    add column if not exists is_category_cover boolean not null default false;

-- At most one cover per category.
create unique index if not exists wallpapers_one_cover_per_category
    on public.wallpapers (category) where is_category_cover;

-- A new column at the end, so apps reading the current columns decode as before.
create or replace view public.catalog as
    select id, kind, title, category, video_path, image_path, thumbnail_path, duration_seconds,
           width, height, creator_name, creator_url, is_featured, sort_order, created_at, is_category_cover
    from public.wallpapers
    where is_published;

revoke all on public.catalog from anon, authenticated;
grant select on public.catalog to anon, authenticated;
