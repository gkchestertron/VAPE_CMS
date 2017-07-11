-- add private user account table
create table vape_private.user_account (
  user_id        integer primary key references vape.user(id) on delete cascade,
  email            text not null unique check (email ~* '^.+@.+\..+$'),
  password_hash    text not null
);

comment on table vape_private.user_account is 'Private information about a user’s account.';
comment on column vape_private.user_account.user_id is 'The id of the user associated with this account.';
comment on column vape_private.user_account.email is 'The email address of the user.';
comment on column vape_private.user_account.password_hash is 'An opaque hash of the user’s password.';

-- register user function
create function vape.register_user(
  first_name text,
  last_name text,
  email text,
  password text
) returns vape.user as $$
declare
  user vape.user;
begin
  insert into vape.user (first_name, last_name) values
    (first_name, last_name)
    returning * into user;

  insert into vape_private.user_account (user_id, email, password_hash) values
    (user.id, email, crypt(password, gen_salt('bf')));

  return user;
end;
$$ language plpgsql strict security definer;

comment on function vape.register_user(text, text, text, text) is 'Registers a single user and creates an account in our forum.';

-- create some roles
create role vape_postgraphql login password 'change this before migrate';
create role vape_anonymous;
grant vape_anonymous to vape_postgraphql;
create role vape_user;
grant vape_user to vape_postgraphql;
create role vape_admin;
grant vape_admin to vape_postgraphql;

-- create token type
create type vape.jwt_token as (
  role text,
  user_id integer
);

-- add auth function
create function vape.authenticate(
  email text,
  password text
) returns vape.jwt_token as $$
declare
  account vape_private.user_account;
begin
  select a.* into account
  from vape_private.user_account as a
  where a.email = $1;

  if account.password_hash = crypt(password, account.password_hash) then
    return ('vape_user', account.user_id)::vape.jwt_token;
  else
    return null;
  end if;
end;
$$ language plpgsql strict security definer;

comment on function vape.authenticate(text, text) is 'Creates a JWT token that will securely identify a user and give them certain permissions.';

-- add  current user function
create function vape.current_user() returns vape.user as $$
  select *
  from vape.user
  where id = current_setting('jwt.claims.user_id')::integer
$$ language sql stable;

comment on function vape.current_user() is 'Gets the user who was identified by our JWT.';

-- grants
-- after schema creation and before function creation
alter default privileges revoke execute on functions from public;

grant usage on schema vape to vape_anonymous, vape_user;

grant select on table vape.user to vape_anonymous, vape_user;
grant update, delete on table vape.user to vape_user;

grant select on table vape.post to vape_anonymous, vape_user;
grant insert, update, delete on table vape.post to vape_user;
grant usage on sequence vape.post_id_seq to vape_user;

grant execute on function vape.user_full_name(vape.user) to vape_anonymous, vape_user;
grant execute on function vape.post_summary(vape.post, integer, text) to vape_anonymous, vape_user;
grant execute on function vape.user_latest_post(vape.user) to vape_anonymous, vape_user;
grant execute on function vape.search_posts(text) to vape_anonymous, vape_user;
grant execute on function vape.authenticate(text, text) to vape_anonymous, vape_user;
grant execute on function vape.current_user() to vape_anonymous, vape_user;

grant execute on function vape.register_user(text, text, text, text) to vape_anonymous;

-- enable row-level security
alter table vape.user enable row level security;
alter table vape.post enable row level security;

-- read policy for anybody
create policy select_user on vape.user for select
  using (true);

create policy select_post on vape.post for select
  using (true);

-- write/delete policies for logged in users on their own accts
create policy update_user on vape.user for update to vape_user
  using (id = current_setting('jwt.claims.user_id')::integer);

create policy delete_user on vape.user for delete to vape_user
  using (id = current_setting('jwt.claims.user_id')::integer);

-- post policies
create policy insert_post on vape.post for insert to vape_user
  with check (author_id = current_setting('jwt.claims.user_id')::integer);

create policy update_post on vape.post for update to vape_user
  using (author_id = current_setting('jwt.claims.user_id')::integer);

create policy delete_post on vape.post for delete to vape_user
  using (author_id = current_setting('jwt.claims.user_id')::integer);
