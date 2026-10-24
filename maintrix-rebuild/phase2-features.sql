-- Maintrix Phase 2 — automatic badges, DM + live-debate notifications,
-- private realtime channels (typing / voice presence), push delivery hook.
-- Safe to re-run.

-- ───────────────────────── badges: catalog ─────────────────────────
create table if not exists badge_catalog (
  label  text primary key,
  grp    text not null,
  icon   text, color text, style text, rarity text,
  metric text,                 -- null = special rule (Founding Member)
  goal   int  not null default 0,
  sort   int  not null default 0
);
alter table badge_catalog enable row level security;
drop policy if exists badge_catalog_read on badge_catalog;
create policy badge_catalog_read on badge_catalog for select using (true);

insert into badge_catalog (label, grp, icon, color, style, rarity, metric, goal, sort) values
  ('First Words', 'Conversation', 'badge', '#4a9eff', 'glow', 'common', 'messages', 1, 0),
  ('Conversationalist', 'Conversation', 'chat', '#4a9eff', 'gradient', 'rare', 'messages', 100, 1),
  ('Wordsmith', 'Conversation', 'feather', '#a855f7', 'holo', 'epic', 'messages', 500, 2),
  ('Voice of the Nexus', 'Conversation', 'nexus', '#ed2e44', 'neon', 'legendary', 'messages', 1000, 3),
  ('Living Legend', 'Conversation', 'nexus', '#ff2d55', 'void', 'mythic', 'messages', 5000, 4),
  ('On Air', 'Conversation', 'mic', '#f0663b', 'ember', 'common', 'voice', 1, 5),
  ('Broadcaster', 'Conversation', 'mic', '#f15bb5', 'neon', 'rare', 'voice', 25, 6),
  ('Pollster', 'Conversation', 'grid', '#3ba55d', 'glow', 'common', 'polls', 1, 7),
  ('Census Taker', 'Conversation', 'grid', '#2a9d8f', 'frost', 'rare', 'polls', 10, 8),
  ('Reactor', 'Reactions & likes', 'bolt', '#fb5607', 'ember', 'common', 'reacts_given', 50, 9),
  ('Hype Machine', 'Reactions & likes', 'rocket', '#ff006e', 'neon', 'epic', 'reacts_given', 500, 10),
  ('Crowd Pleaser', 'Reactions & likes', 'heart', '#ffbe0b', 'gradient', 'rare', 'reacts_rcv', 25, 11),
  ('Standing Ovation', 'Reactions & likes', 'megaphone', '#ffd60a', 'gold', 'legendary', 'reacts_rcv', 250, 12),
  ('Generous', 'Reactions & likes', 'handshake', '#ff9e00', 'glow', 'common', 'likes_given', 25, 13),
  ('Magnetic', 'Reactions & likes', 'sparkle', '#c084fc', 'holo', 'rare', 'likers', 10, 14),
  ('Icon', 'Reactions & likes', 'crown', '#f0b232', 'gold', 'legendary', 'likers', 50, 15),
  ('First Post', 'Creation', 'badge', '#3ba55d', 'glow', 'common', 'posts', 1, 16),
  ('Creator', 'Creation', 'feed', '#f0b232', 'gold', 'rare', 'posts', 10, 17),
  ('Prolific', 'Creation', 'sparkle', '#22d3ee', 'aurora', 'epic', 'posts', 50, 18),
  ('Director', 'Creation', 'live', '#ff2d55', 'neon', 'rare', 'videos', 1, 19),
  ('Auteur', 'Creation', 'camera', '#ff2d55', 'neon', 'epic', 'videos', 5, 20),
  ('Admired', 'Creation', 'heart', '#ff5a8a', 'glow', 'rare', 'post_likes_rcv', 10, 21),
  ('Beloved', 'Creation', 'heart', '#f0b232', 'gold', 'epic', 'post_likes_rcv', 100, 22),
  ('Commentator', 'Creation', 'chat', '#3a86ff', 'glow', 'common', 'comments', 10, 23),
  ('Critic', 'Creation', 'feather', '#8338ec', 'holo', 'epic', 'comments', 100, 24),
  ('First Friend', 'Connection', 'handshake', '#3ba55d', 'glow', 'common', 'friends', 1, 25),
  ('Social Butterfly', 'Connection', 'handshake', '#a855f7', 'glow', 'rare', 'friends', 10, 26),
  ('Connector', 'Connection', 'people', '#22d3ee', 'aurora', 'epic', 'friends', 25, 27),
  ('Community Pillar', 'Connection', 'mountain', '#f0b232', 'gold', 'legendary', 'friends', 50, 28),
  ('Networker', 'Connection', 'globe', '#00bbf9', 'frost', 'rare', 'dms', 10, 29),
  ('Spark', 'Connection', 'flame', '#f0b232', 'ember', 'common', 'dm_streak', 3, 30),
  ('Kindred', 'Connection', 'flame', '#f0663b', 'ember', 'rare', 'dm_streak', 7, 31),
  ('Inseparable', 'Connection', 'flame', '#ff2d55', 'gradient', 'epic', 'dm_streak', 30, 32),
  ('Eternal Bond', 'Connection', 'infinity', '#f0b232', 'gold', 'legendary', 'dm_streak', 100, 33),
  ('Week Warrior', 'Consistency', 'flame', '#f0663b', 'glow', 'rare', 'streak', 7, 34),
  ('Streak Legend', 'Consistency', 'flame', '#ed2e44', 'glow', 'epic', 'streak', 30, 35),
  ('Unbreakable', 'Consistency', 'bolt', '#ff2d55', 'void', 'legendary', 'streak', 100, 36),
  ('Relentless', 'Consistency', 'sun', '#ff7b00', 'void', 'mythic', 'streak', 365, 37),
  ('Veteran', 'Consistency', 'shield', '#94a3b8', 'silver', 'rare', 'days', 30, 38),
  ('Old Guard', 'Consistency', 'anchor', '#94a3b8', 'silver', 'epic', 'days', 180, 39),
  ('One Year', 'Consistency', 'star', '#f0b232', 'gold', 'legendary', 'days', 365, 40),
  ('Debate Debut', 'Debate', 'swords', '#3ba55d', 'glow', 'common', 'debates', 1, 41),
  ('First Victory', 'Debate', 'trophy', '#3ba55d', 'glow', 'rare', 'wins', 1, 42),
  ('Debate Champion', 'Debate', 'trophy', '#f0663b', 'gradient', 'epic', 'wins', 10, 43),
  ('Orator', 'Debate', 'medal', '#f0b232', 'gold', 'legendary', 'wins', 25, 44),
  ('Warlord', 'Debate', 'swords', '#d00000', 'ember', 'legendary', 'wins', 50, 45),
  ('Expert Debater', 'Debate', 'star', '#f0663b', 'neon', 'epic', 'elo', 1400, 46),
  ('Grandmaster', 'Debate', 'crown', '#f0b232', 'gold', 'legendary', 'elo', 1600, 47),
  ('Legend', 'Debate', 'gem', '#c77dff', 'void', 'mythic', 'elo', 1800, 48),
  ('Ranked Contender', 'Debate', 'fist', '#4a9eff', 'frost', 'common', 'ranked_played', 1, 49),
  ('Ranked Victor', 'Debate', 'trophy', '#f0b232', 'gold', 'rare', 'ranked_wins', 1, 50),
  ('Juror', 'Debate', 'eye', '#06d6a0', 'glow', 'common', 'votes', 10, 51),
  ('Kingmaker', 'Debate', 'crown', '#06d6a0', 'aurora', 'epic', 'votes', 100, 52),
  ('Self-Aware', 'Identity & building', 'yinyang', '#22d3ee', 'aurora', 'common', 'personality', 1, 53),
  ('Fully Realised', 'Identity & building', 'compass', '#22d3ee', 'aurora', 'common', 'profile', 1, 54),
  ('Founder', 'Identity & building', 'crown', '#a855f7', 'holo', 'common', 'servers', 1, 55),
  ('Architect', 'Identity & building', 'key', '#a855f7', 'holo', 'rare', 'servers', 3, 56),
  ('Founding Member', 'Identity & building', 'sparkle', '#f0b232', 'glow', 'legendary', null, 0, 57),
  ('Collector', 'Collection', 'gem', '#48bfe3', 'frost', 'rare', 'badges', 10, 58),
  ('Curator', 'Collection', 'book', '#b8c0ff', 'holo', 'epic', 'badges', 25, 59),
  ('Completionist', 'Collection', 'star', '#fee440', 'void', 'mythic', 'badges', 40, 60)
on conflict (label) do update set grp = excluded.grp, icon = excluded.icon, color = excluded.color,
  style = excluded.style, rarity = excluded.rarity, metric = excluded.metric, goal = excluded.goal, sort = excluded.sort;

-- one copy of each badge per person
create unique index if not exists badges_user_label_uq on badges (user_id, label);

-- throttle table for award checks (kept off profiles so checks don't spam realtime)
create table if not exists badge_checks (
  user_id    uuid primary key references profiles(id) on delete cascade,
  checked_at timestamptz not null default now()
);
alter table badge_checks enable row level security;   -- no policies: internal only

-- indexes the metric counts lean on
create index if not exists messages_author_idx          on messages (author_id, created_at);
create index if not exists posts_author_idx             on posts (author_id, created_at);
create index if not exists post_comments_author_idx     on post_comments (author_id);
create index if not exists message_reactions_user_idx   on message_reactions (user_id);
create index if not exists message_reactions_msg_idx    on message_reactions (message_id);
create index if not exists post_likes_user_idx          on post_likes (user_id);
create index if not exists post_likes_post_idx          on post_likes (post_id);
create index if not exists user_likes_liked_idx         on user_likes (liked_id);
create index if not exists polls_author_idx             on polls (author_id);
create index if not exists debate_votes_voter_idx       on debate_votes (voter_id);
create index if not exists rooms_owner_idx              on rooms (owner_id);
create index if not exists room_members_user_idx        on room_members (user_id);
create index if not exists notifications_user_idx       on notifications (user_id, created_at desc);
create index if not exists push_subscriptions_user_idx  on push_subscriptions (user_id);

-- ───────────────────────── badges: metrics ─────────────────────────
create or replace function _badge_metrics(uid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p profiles; r jsonb;
begin
  select * into p from profiles where id = uid;
  if not found then return '{}'::jsonb; end if;
  r := jsonb_build_object(
    'messages',      (select count(*) from messages where author_id = uid and not coalesce(is_system, false)),
    'voice',         (select count(*) from messages where author_id = uid and media_kind = 'audio'),
    'polls',         (select count(*) from polls where author_id = uid),
    'reacts_given',  (select count(distinct message_id) from message_reactions where user_id = uid),
    'reacts_rcv',    (select count(*) from message_reactions x join messages m on m.id = x.message_id
                       where m.author_id = uid and x.user_id <> uid),
    'likes_given',   (select count(*) from user_likes where liker_id = uid)
                   + (select count(*) from post_likes where user_id = uid),
    'likers',        (select count(distinct liker_id) from user_likes where liked_id = uid and liker_id <> uid),
    'posts',         (select count(*) from posts where author_id = uid),
    'videos',        (select count(*) from posts where author_id = uid and media_kind = 'video'),
    'post_likes_rcv',(select count(*) from post_likes l join posts po on po.id = l.post_id
                       where po.author_id = uid and l.user_id <> uid),
    'comments',      (select count(*) from post_comments where author_id = uid)
  ) || jsonb_build_object(
    'friends',       (select count(*) from friendships where uid in (user_a, user_b)),
    'dms',           (select count(distinct m.room_id) from messages m join rooms ro on ro.id = m.room_id
                       where m.author_id = uid and ro.kind = 'dm'),
    'dm_streak',     coalesce((select max(s.streak_count) from dm_streaks s
                       join room_members rm on rm.room_id = s.room_id and rm.user_id = uid), 0),
    -- longest run of consecutive (UTC) days with a message or a post
    'streak',        coalesce((select max(n) from (
                       select count(*) n from (
                         select d, d - (row_number() over (order by d))::int g from (
                           select (created_at at time zone 'utc')::date d from messages where author_id = uid
                           union
                           select (created_at at time zone 'utc')::date from posts where author_id = uid
                         ) a
                       ) b group by g) c), 0),
    'days',          greatest(0, (now() at time zone 'utc')::date - (p.created_at at time zone 'utc')::date),
    'debates',       coalesce(p.debate_wins, 0) + coalesce(p.debate_losses, 0) + coalesce(p.debate_ties, 0),
    'wins',          coalesce(p.debate_wins, 0),
    'elo',           coalesce(p.elo, 1000),
    'ranked_played', (select count(*) from debates where ranked and status = 'ended' and uid in (creator_id, opponent_id)),
    'ranked_wins',   (select count(*) from debates where ranked and status = 'ended' and winner_id = uid),
    'votes',         (select count(distinct debate_id) from debate_votes where voter_id = uid)
  ) || jsonb_build_object(
    'personality',   case when coalesce(p.mbti, '') <> '' and coalesce(p.enneagram_core, '') <> ''
                           and coalesce(p.temperament_dominant, '') <> '' then 1 else 0 end,
    'profile',       case when coalesce(p.avatar_path, '') <> '' and coalesce(p.bio, '') <> ''
                           and coalesce(p.status_line, '') <> '' then 1 else 0 end,
    'servers',       (select count(*) from rooms where owner_id = uid and kind = 'server'),
    'badges',        (select count(*) from badges where user_id = uid),
    'founding',      case when (select count(*) from profiles q where q.created_at < p.created_at) < 100 then 1 else 0 end
  );
  return r;
end $$;
revoke all on function _badge_metrics(uuid) from public, anon, authenticated;

-- ───────────────────────── badges: awarding ─────────────────────────
create or replace function award_badges(uid uuid, force boolean default false) returns int
language plpgsql security definer set search_path = public as $$
declare m jsonb; b record; n int := 0; last_at timestamptz; held int;
begin
  if uid is null then return 0; end if;
  if not force then
    select checked_at into last_at from badge_checks where user_id = uid;
    if last_at is not null and last_at > now() - interval '5 seconds' then return 0; end if;
  end if;
  insert into badge_checks (user_id, checked_at) values (uid, now())
    on conflict (user_id) do update set checked_at = now();

  m := _badge_metrics(uid);
  if m = '{}'::jsonb then return 0; end if;

  for b in
    select c.* from badge_catalog c
    where c.metric is distinct from 'badges'
      and case when c.metric is null then coalesce((m->>'founding')::int, 0) >= 1
               else coalesce((m->>c.metric)::numeric, 0) >= c.goal end
      and not exists (select 1 from badges x where x.user_id = uid and x.label = c.label)
    order by c.sort
  loop
    insert into badges (user_id, label, icon, color, style, rarity, is_public)
    values (uid, b.label, b.icon, b.color, b.style, b.rarity, true)
    on conflict (user_id, label) do nothing;
    n := n + 1;
  end loop;

  -- collection badges count what is held after this round
  select count(*) into held from badges where user_id = uid;
  for b in
    select c.* from badge_catalog c
    where c.metric = 'badges' and held >= c.goal
      and not exists (select 1 from badges x where x.user_id = uid and x.label = c.label)
    order by c.goal
  loop
    insert into badges (user_id, label, icon, color, style, rarity, is_public)
    values (uid, b.label, b.icon, b.color, b.style, b.rarity, true)
    on conflict (user_id, label) do nothing;
    n := n + 1; held := held + 1;
  end loop;
  return n;
end $$;
revoke all on function award_badges(uuid, boolean) from public, anon, authenticated;

-- progress screen: check (and award) on open, then report every metric
create or replace function my_badge_progress() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
begin
  if auth.uid() is null then return '{}'::jsonb; end if;
  perform award_badges(auth.uid(), true);
  return _badge_metrics(auth.uid()) - 'founding';
end $$;
grant execute on function my_badge_progress() to authenticated;

-- activity → award check (throttled; profile/server/friend/debate-end changes force a check)
create or replace function trg_badge_check() returns trigger
language plpgsql security definer set search_path = public as $$
declare a uuid; b uuid; f boolean := false;
begin
  if tg_table_name in ('messages', 'posts', 'post_comments', 'polls') then
    a := new.author_id;
  elsif tg_table_name = 'post_likes' then
    a := new.user_id; select author_id into b from posts where id = new.post_id;
  elsif tg_table_name = 'user_likes' then
    a := new.liker_id; b := new.liked_id;
  elsif tg_table_name = 'message_reactions' then
    a := new.user_id; select author_id into b from messages where id = new.message_id;
  elsif tg_table_name = 'friendships' then
    a := new.user_a; b := new.user_b; f := true;
  elsif tg_table_name = 'debate_votes' then
    a := new.voter_id;
  elsif tg_table_name = 'rooms' then
    a := new.owner_id; f := true;
  elsif tg_table_name = 'profiles' then
    a := new.id; f := true;
  elsif tg_table_name = 'debates' then
    a := new.creator_id; b := new.opponent_id; f := true;
  end if;
  perform award_badges(a, f);
  if b is not null and b is distinct from a then perform award_badges(b, f); end if;
  return null;
exception when others then
  return null;   -- never let badge bookkeeping break the user's action
end $$;

drop trigger if exists zz_badge_check on messages;
create trigger zz_badge_check after insert on messages for each row execute function trg_badge_check();
drop trigger if exists zz_badge_check on posts;
create trigger zz_badge_check after insert on posts for each row execute function trg_badge_check();
drop trigger if exists zz_badge_check on post_comments;
create trigger zz_badge_check after insert on post_comments for each row execute function trg_badge_check();
drop trigger if exists zz_badge_check on polls;
create trigger zz_badge_check after insert on polls for each row execute function trg_badge_check();
drop trigger if exists zz_badge_check on post_likes;
create trigger zz_badge_check after insert on post_likes for each row execute function trg_badge_check();
drop trigger if exists zz_badge_check on user_likes;
create trigger zz_badge_check after insert on user_likes for each row execute function trg_badge_check();
drop trigger if exists zz_badge_check on message_reactions;
create trigger zz_badge_check after insert on message_reactions for each row execute function trg_badge_check();
drop trigger if exists zz_badge_check on friendships;
create trigger zz_badge_check after insert on friendships for each row execute function trg_badge_check();
drop trigger if exists zz_badge_check on debate_votes;
create trigger zz_badge_check after insert on debate_votes for each row execute function trg_badge_check();
drop trigger if exists zz_badge_check on rooms;
create trigger zz_badge_check after insert on rooms for each row
  when (new.kind = 'server') execute function trg_badge_check();
drop trigger if exists zz_badge_check on profiles;
create trigger zz_badge_check after insert or update of mbti, enneagram_core, temperament_dominant, avatar_path, bio, status_line
  on profiles for each row execute function trg_badge_check();
drop trigger if exists zz_badge_check on debates;
create trigger zz_badge_check after update of status on debates for each row
  when (new.status = 'ended' and old.status is distinct from 'ended') execute function trg_badge_check();

-- badge notifications: the client reads entity.label
create or replace function trg_notify_badge() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notify_user(new.user_id, 'badge', new.awarded_by,
    jsonb_build_object('label', new.label, 'title', new.label, 'icon', new.icon, 'color', new.color));
  return new;
end $$;

-- ───────────────────────── DM / group notifications ─────────────────────────
create or replace function trg_notify_dm() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; u uuid; ent jsonb;
begin
  if coalesce(new.is_system, false) then return null; end if;
  select kind, title into r from rooms where id = new.room_id;
  if r.kind is null or r.kind not in ('dm', 'group') then return null; end if;
  ent := jsonb_build_object('room_id', new.room_id, 'preview', left(coalesce(new.body, ''), 120),
                            'media_kind', new.media_kind, 'group', r.kind = 'group', 'title', r.title);
  for u in
    select rm.user_id from room_members rm
    where rm.room_id = new.room_id and rm.user_id <> new.author_id
      and not exists (select 1 from room_mutes mu where mu.room_id = new.room_id and mu.user_id = rm.user_id)
  loop
    perform notify_user(u, 'dm', new.author_id, ent);
  end loop;
  return null;
end $$;
drop trigger if exists notify_dm on messages;
create trigger notify_dm after insert on messages for each row execute function trg_notify_dm();

-- ───────────────────────── live-debate alerts (opt-in) ─────────────────────────
create or replace function trg_notify_debate_live() returns trigger
language plpgsql security definer set search_path = public as $$
declare an text; bn text;
begin
  if new.status = 'active' and new.opponent_id is not null
     and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    select coalesce(name, handle::text) into an from profiles where id = new.creator_id;
    select coalesce(name, handle::text) into bn from profiles where id = new.opponent_id;
    insert into notifications (user_id, type, kind, actor_id, entity, body)
    select p.id, 'debate_live', 'debate_live', new.creator_id,
           jsonb_build_object('debate_id', new.id, 'room_id', new.room_id, 'title', new.title,
                              'ranked', coalesce(new.ranked, false), 'a', an, 'b', bn),
           left(coalesce(new.title, ''), 120)
    from profiles p
    where p.notif_prefs -> 'debate_live' = 'true'::jsonb
      and p.id is distinct from new.creator_id and p.id is distinct from new.opponent_id;
  end if;
  return null;
end $$;
drop trigger if exists notify_debate_live on debates;
create trigger notify_debate_live after insert or update of status on debates
  for each row execute function trg_notify_debate_live();

-- ───────────────────────── private realtime channels ─────────────────────────
-- The client opens typing:<room> and voice:<id> as private channels; without
-- policies on realtime.messages those subscriptions are refused.
drop policy if exists mx_private_channels_read on realtime.messages;
create policy mx_private_channels_read on realtime.messages for select to authenticated
  using ((select realtime.topic()) like 'typing:%' or (select realtime.topic()) like 'voice:%');
drop policy if exists mx_private_channels_write on realtime.messages;
create policy mx_private_channels_write on realtime.messages for insert to authenticated
  with check ((select realtime.topic()) like 'typing:%' or (select realtime.topic()) like 'voice:%');

-- ───────────────────────── push delivery hook ─────────────────────────
create extension if not exists pg_net;

create or replace function trg_push_notification() returns trigger
language plpgsql security definer set search_path = public as $$
declare sec text;
begin
  if not exists (select 1 from push_subscriptions where user_id = new.user_id) then return null; end if;
  select decrypted_secret into sec from vault.decrypted_secrets where name = 'push_hook_secret' limit 1;
  if sec is null then return null; end if;
  perform net.http_post(
    url     := 'https://dvrcrwyjqlrowsnevduz.supabase.co/functions/v1/send-push',
    body    := jsonb_build_object('id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', sec),
    timeout_milliseconds := 8000);
  return null;
exception when others then
  return null;   -- push is best-effort; never block the notification insert
end $$;
drop trigger if exists push_notification on notifications;
create trigger push_notification after insert on notifications
  for each row execute function trg_push_notification();

-- ───────────────────────── backfill ─────────────────────────
select award_badges(id, true) from profiles;
