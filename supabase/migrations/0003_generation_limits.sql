-- Server-side limits for AI wallpapers (Create).
--
-- Every generation spends one rewarded ad that Google has confirmed to the `ad-reward` function
-- (AdMob server-side verification), at most a few per install a day and a fixed number across everyone,
-- so AI costs stay tied to ad views whatever a modified app or a script sends.
-- Only the Edge Functions touch these tables, with the service role; the API roles get nothing.

create table if not exists public.ad_rewards (
    -- AdMob's transaction ID, so a retried callback is stored once.
    transaction_id text primary key,
    -- A random ID the app keeps for itself (not tied to the person), sent to AdMob as the SSV user ID.
    install_id text not null,
    -- A one-off ID the app sent as the SSV custom data for this ad, and then with its generate request.
    nonce text not null,
    created_at timestamptz not null default now(),
    redeemed_at timestamptz
);
create index if not exists ad_rewards_nonce on public.ad_rewards (nonce, install_id);
create index if not exists ad_rewards_redeemed on public.ad_rewards (redeemed_at) where redeemed_at is not null;

-- Generated images someone flagged from the app. Only the description and style are kept, never the image.
create table if not exists public.generation_reports (
    id bigint generated always as identity primary key,
    install_id text not null check (char_length(install_id) <= 64),
    prompt text not null check (char_length(prompt) <= 600),
    reason text not null check (reason in ('sexual', 'violent', 'hateful', 'other')),
    created_at timestamptz not null default now()
);

alter table public.ad_rewards enable row level security;
alter table public.generation_reports enable row level security;
revoke all on public.ad_rewards, public.generation_reports from anon, authenticated;

-- Spends the reward for one generation, or says why it can't: 'ok', 'no_reward', 'daily_limit' or 'global_limit'.
-- Limits count redeemed rewards since midnight UTC.
create or replace function public.redeem_ad_reward(p_nonce text, p_install text, p_daily_limit int, p_global_limit int)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    today timestamptz := date_trunc('day', now(), 'UTC');
    reward text;
begin
    -- One redemption at a time, so two requests can't both slip under a limit.
    perform pg_advisory_xact_lock(hashtext('redeem_ad_reward'));
    if (select count(*) from ad_rewards where redeemed_at >= today) >= p_global_limit then
        return 'global_limit';
    end if;
    if (select count(*) from ad_rewards where install_id = p_install and redeemed_at >= today) >= p_daily_limit then
        return 'daily_limit';
    end if;
    select transaction_id into reward
    from ad_rewards
    where nonce = p_nonce and install_id = p_install and redeemed_at is null
      and created_at > now() - interval '1 hour'
    limit 1;
    if reward is null then
        return 'no_reward';
    end if;
    update ad_rewards set redeemed_at = now() where transaction_id = reward;
    return 'ok';
end;
$$;

-- Gives the ad back when the server, not the person's description, made the generation fail.
create or replace function public.refund_ad_reward(p_nonce text, p_install text)
returns void
language sql
security definer
set search_path = public
as $$
    update ad_rewards set redeemed_at = null where nonce = p_nonce and install_id = p_install;
$$;

revoke all on function public.redeem_ad_reward(text, text, int, int) from public, anon, authenticated;
revoke all on function public.refund_ad_reward(text, text) from public, anon, authenticated;
