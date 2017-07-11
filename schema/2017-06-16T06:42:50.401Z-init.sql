-- create schemas
create schema vape;
create schema vape_private;

-- create user table
create table vape.user (
  id               serial primary key,
  first_name       text not null check (char_length(first_name) < 80),
  last_name        text check (char_length(last_name) < 80),
  about            text,
  created_at       timestamp default now()
);

-- add comments on user table
comment on table vape.user is 'A user of the forum.';
comment on column vape.user.id is 'The primary unique identifier for the user.';
comment on column vape.user.first_name is 'The user’s first name.';
comment on column vape.user.last_name is 'The user’s last name.';
comment on column vape.user.about is 'A short description about the user, written by the user.';
comment on column vape.user.created_at is 'The time this user was created.';

-- create a new enum type
create type vape.post_topic as enum (
  'discussion',
  'inspiration',
  'help',
  'showcase'
);

-- create the post table
create table vape.post (
  id               serial primary key,
  author_id        integer not null references vape.user(id),
  headline         text not null check (char_length(headline) < 280),
  body             text,
  topic            vape.post_topic,
  created_at       timestamp default now()
);

-- add some annotations
comment on table vape.post is 'A forum post written by a user.';
comment on column vape.post.id is 'The primary key for the post.';
comment on column vape.post.headline is 'The title written by the user.';
comment on column vape.post.author_id is 'The id of the author user.';
comment on column vape.post.topic is 'The topic this has been posted in.';
comment on column vape.post.body is 'The main body text of our post.';
comment on column vape.post.created_at is 'The time this post was created.';

-- create full name function
create function vape.user_full_name(user vape.user) returns text as $$
	select user.first_name || ' ' || user.last_name
$$ language sql stable;

comment on function vape.user_full_name(vape.user) is 'A user’s full name which is a concatenation of their first and last name.';

-- create post summary function
create function vape.post_summary(
  post vape.post,
  length int default 50,
  omission text default '…'
) returns text as $$
  select case
    when post.body is null then null
    else substr(post.body, 0, length) || omission
  end
$$ language sql stable;

comment on function vape.post_summary(vape.post, int, text) is 'A truncated version of the body for summaries.';

-- latest post function
create function vape.user_latest_post(user vape.user) returns vape.post as $$
  select post.*
  from vape.post as post
  where post.author_id = user.id
  order by created_at desc
  limit 1
$$ language sql stable;

comment on function vape.user_latest_post(vape.user) is 'Get’s the latest post written by the user.';

-- search post function
create function vape.search_posts(search text) returns setof vape.post as $$
  select post.*
  from vape.post as post
  where post.headline ilike ('%' || search || '%') or post.body ilike ('%' || search || '%')
$$ language sql stable;

comment on function vape.search_posts(text) is 'Returns posts containing a given search term.';

-- add updated columns
alter table vape.user add column updated_at timestamp default now();
alter table vape.post add column updated_at timestamp default now();

-- add triggers and function for update
create function vape_private.set_updated_at() returns trigger as $$
begin
  new.updated_at := current_timestamp;
  return new;
end;
$$ language plpgsql;

create trigger user_updated_at before update
  on vape.user
  for each row
  execute procedure vape_private.set_updated_at();

create trigger post_updated_at before update
  on vape.post
  for each row
  execute procedure vape_private.set_updated_at();
