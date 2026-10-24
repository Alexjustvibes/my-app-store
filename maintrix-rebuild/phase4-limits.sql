-- Maintrix — anti-spam limits (2026-10-24). Applied live; kept for rebuilds. Safe to re-run.
-- Text caps on every user-written field, rate limits on posts/messages/comments, upload rules.
-- Admins and server-side functions are exempt from the rate limits.

create or replace function public._cap(val text, maxlen int, label text) returns void
language plpgsql immutable as $$
begin
  if val is not null and char_length(val) > maxlen then
    raise exception '% can be up to % characters', label, maxlen using errcode = '22001';
  end if;
end $$;

create or replace function public._rate_ok(tbl text, uid uuid, max_n int, win interval) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare n int;
begin
  if tbl = 'posts' then select count(*) into n from posts where author_id = uid and created_at > now() - win;
  elsif tbl = 'messages' then select count(*) into n from messages where author_id = uid and created_at > now() - win and not coalesce(is_system, false);
  elsif tbl = 'post_comments' then select count(*) into n from post_comments where author_id = uid and created_at > now() - win;
  end if;
  return coalesce(n, 0) < max_n;
end $$;
revoke all on function public._rate_ok(text, uuid, int, interval) from public, anon, authenticated;
grant execute on function public._rate_ok(text, uuid, int, interval) to authenticated;

-- must not be SECURITY DEFINER: it reads the caller's role
create or replace function public._is_app_user() returns boolean language sql stable as $$
  select current_user in ('authenticated', 'anon') and not coalesce(public.is_admin(), false)
$$;

create or replace function public.limit_posts() returns trigger language plpgsql as $$
begin
  perform _cap(new.body, 2000, 'Posts');
  perform _cap(new.caption, 60, 'Captions');
  if tg_op = 'INSERT' and _is_app_user() and not _rate_ok('posts', new.author_id, 5, interval '10 minutes') then
    raise exception 'Too many posts — you can post again in a few minutes' using errcode = 'P0001';
  end if;
  return new;
end $$;
create or replace trigger a_limit_posts before insert or update of body, caption on posts for each row execute function limit_posts();

create or replace function public.limit_messages() returns trigger language plpgsql as $$
begin
  perform _cap(new.body, 4000, 'Messages');
  if tg_op = 'INSERT' and not coalesce(new.is_system, false) and _is_app_user()
     and not _rate_ok('messages', new.author_id, 30, interval '1 minute') then
    raise exception 'Too many messages — slow down' using errcode = 'P0001';
  end if;
  return new;
end $$;
create or replace trigger a_limit_messages before insert or update of body on messages for each row execute function limit_messages();

create or replace function public.limit_comments() returns trigger language plpgsql as $$
begin
  perform _cap(new.body, 1000, 'Comments');
  if tg_op = 'INSERT' and _is_app_user() and not _rate_ok('post_comments', new.author_id, 10, interval '1 minute') then
    raise exception 'Too many comments — slow down' using errcode = 'P0001';
  end if;
  return new;
end $$;
create or replace trigger a_limit_comments before insert or update of body on post_comments for each row execute function limit_comments();

create or replace function public.limit_profiles() returns trigger language plpgsql as $$
begin
  perform _cap(new.bio, 200, 'Bios');
  perform _cap(new.status_line, 60, 'Status');
  perform _cap(new.name, 40, 'Names');
  perform _cap(new.handle::text, 20, 'Usernames');
  return new;
end $$;
create or replace trigger a_limit_profiles before insert or update of bio, status_line, name, handle on profiles for each row execute function limit_profiles();

create or replace function public.limit_misc() returns trigger language plpgsql as $$
begin
  if tg_table_name = 'debates' then
    perform _cap(new.title, 120, 'Debate titles'); perform _cap(new.description, 1000, 'Debate descriptions'); perform _cap(new."desc", 1000, 'Debate descriptions');
  elsif tg_table_name = 'polls' then perform _cap(new.question, 200, 'Poll questions');
  elsif tg_table_name = 'events' then perform _cap(new.title, 100, 'Event titles');
  elsif tg_table_name = 'feedback' then perform _cap(new.body, 2000, 'Feedback');
  elsif tg_table_name = 'rooms' then perform _cap(new.title, 120, 'Names');
  elsif tg_table_name = 'voice_channels' then perform _cap(new.name, 60, 'Channel names');
  end if;
  return new;
end $$;
create or replace trigger a_limit_misc before insert or update on debates for each row execute function limit_misc();
create or replace trigger a_limit_misc before insert or update on polls for each row execute function limit_misc();
create or replace trigger a_limit_misc before insert or update on events for each row execute function limit_misc();
create or replace trigger a_limit_misc before insert or update on feedback for each row execute function limit_misc();
create or replace trigger a_limit_misc before insert or update of title on rooms for each row execute function limit_misc();
create or replace trigger a_limit_misc before insert or update on voice_channels for each row execute function limit_misc();

-- uploads: 50 MB per file, only the media types the app uploads
update storage.buckets set file_size_limit = 52428800,
  allowed_mime_types = array['image/png','image/jpeg','image/gif','image/webp','video/mp4','video/quicktime','video/webm',
                             'audio/webm','audio/mp4','audio/ogg','audio/mpeg','audio/wav']
where id in ('media', 'attachments');
