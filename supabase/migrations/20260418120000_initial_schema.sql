-- SplitMate core schema, RLS, and profile bootstrap
-- Run via Supabase CLI or SQL Editor

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  email text,
  avatar_url text,
  created_at timestamptz not null default now()
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id) on delete restrict,
  group_type text not null default 'household'
    check (group_type in ('household', 'pair'))
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  from_user uuid not null references auth.users (id) on delete cascade,
  to_user uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now(),
  unique (from_user, to_user),
  check (from_user <> to_user)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  paid_by uuid not null references auth.users (id) on delete restrict,
  amount numeric(14, 2) not null check (amount > 0),
  description text not null default '',
  expense_date date not null default (current_date at time zone 'utc'),
  created_at timestamptz not null default now()
);

create table public.splits (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  amount_owed numeric(14, 2) not null check (amount_owed >= 0),
  unique (expense_id, user_id)
);

create table public.push_tokens (
  user_id uuid not null references auth.users (id) on delete cascade,
  token text not null,
  platform text not null default 'ios',
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

create table public.notification_log (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  sent_at timestamptz not null default now(),
  unique (expense_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index idx_group_members_user on public.group_members (user_id);
create index idx_expenses_group on public.expenses (group_id);
create index idx_splits_expense on public.splits (expense_id);
create index idx_friend_requests_to on public.friend_requests (to_user) where status = 'pending';
create index idx_friend_requests_from on public.friend_requests (from_user);

-- ---------------------------------------------------------------------------
-- Helper: membership check
-- ---------------------------------------------------------------------------
create or replace function public.is_group_member(_group_id uuid, _user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.group_members gm
    where gm.group_id = _group_id and gm.user_id = _user_id
  );
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.friend_requests enable row level security;
alter table public.expenses enable row level security;
alter table public.splits enable row level security;
alter table public.push_tokens enable row level security;
alter table public.notification_log enable row level security;

-- Profiles: discoverable for signed-in users; update own row only
create policy "profiles_select_authenticated"
  on public.profiles for select
  to authenticated
  using (true);

create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Groups: members can read; creator can read before any group_members row exists
-- (needed for insert+return=representation and for group_members insert WITH CHECK subquery)
create policy "groups_select_member"
  on public.groups for select
  to authenticated
  using (
    created_by = auth.uid()
    or public.is_group_member(id, auth.uid())
  );

create policy "groups_insert_authenticated"
  on public.groups for insert
  to authenticated
  with check (created_by = auth.uid());

create policy "groups_update_creator"
  on public.groups for update
  to authenticated
  using (created_by = auth.uid())
  with check (created_by = auth.uid());

-- Group members
create policy "group_members_select_member"
  on public.group_members for select
  to authenticated
  using (public.is_group_member(group_id, auth.uid()));

create policy "group_members_insert"
  on public.group_members for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.groups g
      where g.id = group_id and g.created_by = auth.uid()
    )
    or public.is_group_member(group_id, auth.uid())
  );

create policy "group_members_delete"
  on public.group_members for delete
  to authenticated
  using (
    public.is_group_member(group_id, auth.uid())
    and (
      user_id = auth.uid()
      or exists (
        select 1 from public.groups g
        where g.id = group_id and g.created_by = auth.uid()
      )
    )
  );

-- Friend requests
create policy "friend_requests_select_participant"
  on public.friend_requests for select
  to authenticated
  using (from_user = auth.uid() or to_user = auth.uid());

create policy "friend_requests_insert_sender"
  on public.friend_requests for insert
  to authenticated
  with check (from_user = auth.uid());

create policy "friend_requests_update_participant"
  on public.friend_requests for update
  to authenticated
  using (from_user = auth.uid() or to_user = auth.uid())
  with check (from_user = auth.uid() or to_user = auth.uid());

-- Expenses
create policy "expenses_select_member"
  on public.expenses for select
  to authenticated
  using (public.is_group_member(group_id, auth.uid()));

create policy "expenses_insert_member"
  on public.expenses for insert
  to authenticated
  with check (
    public.is_group_member(group_id, auth.uid())
    and paid_by = auth.uid()
  );

create policy "expenses_update_member"
  on public.expenses for update
  to authenticated
  using (public.is_group_member(group_id, auth.uid()))
  with check (public.is_group_member(group_id, auth.uid()));

create policy "expenses_delete_payer_or_creator"
  on public.expenses for delete
  to authenticated
  using (
    paid_by = auth.uid()
    or exists (
      select 1 from public.groups g
      where g.id = group_id and g.created_by = auth.uid()
    )
  );

-- Splits
create policy "splits_select_member"
  on public.splits for select
  to authenticated
  using (
    exists (
      select 1 from public.expenses e
      where e.id = expense_id and public.is_group_member(e.group_id, auth.uid())
    )
  );

create policy "splits_insert_member"
  on public.splits for insert
  to authenticated
  with check (
    exists (
      select 1 from public.expenses e
      where e.id = expense_id and public.is_group_member(e.group_id, auth.uid())
    )
  );

create policy "splits_update_member"
  on public.splits for update
  to authenticated
  using (
    exists (
      select 1 from public.expenses e
      where e.id = expense_id and public.is_group_member(e.group_id, auth.uid())
    )
  );

create policy "splits_delete_member"
  on public.splits for delete
  to authenticated
  using (
    exists (
      select 1 from public.expenses e
      where e.id = expense_id and public.is_group_member(e.group_id, auth.uid())
    )
  );

-- Push tokens
create policy "push_tokens_own"
  on public.push_tokens for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Notification log: no client access (Edge Function uses service role)
create policy "notification_log_no_client"
  on public.notification_log for select
  to authenticated
  using (false);

-- ---------------------------------------------------------------------------
-- Auth: create profile on signup
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, email)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'username'), ''),
      split_part(coalesce(new.email, 'user'), '@', 1)
    ) || '_' || substr(new.id::text, 1, 8),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
