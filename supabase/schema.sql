-- PaperTrail community-learning backend (Supabase free tier).
-- Paste into the SQL editor of a new Supabase project, then add the project's
-- URL + anon key as the SUPABASE_URL / SUPABASE_ANON_KEY repo secrets.
--
-- Design: devices INSERT anonymized correction events; a scheduled SQL job
-- (pg_cron, no human curation) recomputes per-merchant majority facts into
-- community_merchants, which devices SELECT. The anon role can ONLY insert
-- events and read aggregates — never read raw events.

-- pg_cron must be enabled before the schedule calls at the bottom.
create extension if not exists pg_cron;

-- ───────────────────────── raw contributions ─────────────────────────

create table if not exists correction_events (
    id              bigint generated always as identity primary key,
    install_id      uuid        not null,           -- random per-install, never identity-linked
    merchant_key    text        not null,           -- normalized merchant name
    field_name      text        not null,
    original_value  text        not null,
    corrected_value text        not null,
    document_kind   text        not null,
    source          text        not null,
    confidence      text        not null,
    created_at      timestamptz not null default now()
);

create index if not exists correction_events_merchant_idx on correction_events (merchant_key);
create index if not exists correction_events_created_idx  on correction_events (created_at);

-- Basic abuse control: cap value sizes at the database too (the client also
-- scrubs and caps). Reject anything oversized outright.
alter table correction_events
    add constraint correction_values_capped
    check (char_length(original_value) <= 200 and char_length(corrected_value) <= 200);

alter table correction_events enable row level security;

-- anon key: INSERT only. No select/update/delete — raw events are never
-- readable from devices.
create policy "anon can contribute"
    on correction_events for insert
    to anon
    with check (true);

-- ───────────────────────── majority aggregates ─────────────────────────

create table if not exists community_merchants (
    merchant_key  text primary key,
    display_name  text,
    document_kind text,
    currency      text,
    category      text,
    contributors  integer not null default 0,
    updated_at    timestamptz not null default now()
);

alter table community_merchants enable row level security;

create policy "anon can read aggregates"
    on community_merchants for select
    to anon
    using (true);

-- ───────────────────────── the "ML": majority learning ─────────────────────────
-- Pure SQL aggregation — mode() per merchant per fact, counted only when ≥3
-- DISTINCT installs contributed (poisoning resistance), with a 12-month
-- recency window so the community forgets stale layouts the same way
-- on-device hintStrength does.

create or replace function refresh_community_merchants()
returns void
language sql
security definer
as $$
    insert into community_merchants (merchant_key, display_name, document_kind, currency, category, contributors, updated_at)
    select
        merchant_key,
        mode() within group (order by corrected_value) filter (where field_name = 'merchantName'),
        mode() within group (order by document_kind),
        mode() within group (order by corrected_value) filter (where field_name = 'currency'),
        mode() within group (order by corrected_value) filter (where field_name = 'category'),
        count(distinct install_id)::int,
        now()
    from correction_events
    where created_at > now() - interval '12 months'
    group by merchant_key
    having count(distinct install_id) >= 3
    on conflict (merchant_key) do update set
        display_name  = excluded.display_name,
        document_kind = excluded.document_kind,
        currency      = excluded.currency,
        category      = excluded.category,
        contributors  = excluded.contributors,
        updated_at    = excluded.updated_at;

    -- Forget merchants that no longer clear the bar (window moved on).
    delete from community_merchants cm
    where not exists (
        select 1 from correction_events e
        where e.merchant_key = cm.merchant_key
          and e.created_at > now() - interval '12 months'
        group by e.merchant_key
        having count(distinct e.install_id) >= 3
    );
$$;

-- Run hourly. (pg_cron ships enabled on Supabase; adjust cadence freely.)
select cron.schedule('refresh-community-merchants', '15 * * * *',
                     $$select refresh_community_merchants()$$);

-- Storage hygiene on the 500 MB free tier: drop raw events after 18 months —
-- aggregates persist, and the corrections corpus for adapter training should
-- be exported (CSV download) before expiry if wanted.
select cron.schedule('expire-old-corrections', '30 3 * * 0',
                     $$delete from correction_events where created_at < now() - interval '18 months'$$);
