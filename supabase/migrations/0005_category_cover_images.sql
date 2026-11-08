-- An image made for a category's Explore tile, uploaded in the admin site. The app shows it before a
-- picked wallpaper (0004) or the first wallpaper. Apps that don't read this table keep their tiles as before.

create table if not exists public.category_covers (
    category text primary key check (char_length(btrim(category)) > 0),
    image_path text not null check (image_path like 'covers/%'),
    updated_at timestamptz not null default now()
);

alter table public.category_covers enable row level security;
revoke all on public.category_covers from anon, authenticated;
grant select on public.category_covers to anon, authenticated;
grant insert, update, delete on public.category_covers to authenticated;

drop policy if exists "Category covers are readable by everyone" on public.category_covers;
create policy "Category covers are readable by everyone"
    on public.category_covers
    for select
    to anon, authenticated
    using (true);

drop policy if exists "Admins manage category covers" on public.category_covers;
create policy "Admins manage category covers"
    on public.category_covers
    for all
    to authenticated
    using ((select public.is_admin()))
    with check ((select public.is_admin()));
