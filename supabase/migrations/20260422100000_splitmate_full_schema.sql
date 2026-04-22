-- SplitMate: complete schema for a new Supabase database
-- Replaces prior incremental migrations; run once on an empty project.
-- Includes: core tables, pending invites/members/splits, RLS, expense audit log,
-- auth profile bootstrap, and audit triggers.

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Core tables
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
-- Pending (shadow) user flow
-- ---------------------------------------------------------------------------

create table public.pending_friend_invites (
  id uuid primary key default gen_random_uuid(),
  inviter_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  phone text,
  email text not null,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'cancelled')),
  created_at timestamptz not null default now(),
  unique (inviter_id, email)
);

create table public.pending_group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  pending_invite_id uuid not null references public.pending_friend_invites (id) on delete cascade,
  added_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (group_id, pending_invite_id)
);

create table public.pending_splits (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses (id) on delete cascade,
  pending_invite_id uuid not null references public.pending_friend_invites (id) on delete cascade,
  amount_owed numeric(14, 2) not null check (amount_owed >= 0),
  unique (expense_id, pending_invite_id)
);

-- ---------------------------------------------------------------------------
-- Expense audit log (group_id kept so rows stay readable after expense delete)
-- ---------------------------------------------------------------------------

create table public.expense_audit_log (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  expense_id uuid references public.expenses (id) on delete set null,
  actor_id uuid references auth.users (id) on delete set null,
  action text not null
    check (action in ('expense_updated', 'expense_deleted', 'splits_changed')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index idx_group_members_user on public.group_members (user_id);
create index idx_expenses_group_created on public.expenses (group_id, created_at desc);
create index idx_splits_expense on public.splits (expense_id);
create index idx_friend_requests_to on public.friend_requests (to_user) where status = 'pending';
create index idx_friend_requests_from on public.friend_requests (from_user);

create index idx_pending_friend_invites_inviter
  on public.pending_friend_invites (inviter_id, status, created_at desc);

create index idx_pending_group_members_group
  on public.pending_group_members (group_id, created_at desc);

create index idx_pending_splits_expense on public.pending_splits (expense_id);

create index idx_expense_audit_log_group_created
  on public.expense_audit_log (group_id, created_at desc);

create index idx_expense_audit_log_expense_created
  on public.expense_audit_log (expense_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Helper functions
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

create or replace function public.can_manage_expense(_expense_id uuid, _user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.expenses e
    where e.id = _expense_id
      and (
        public.is_group_member(e.group_id, _user_id)
        or e.paid_by = _user_id
        or exists (
          select 1
          from public.splits s
          where s.expense_id = e.id
            and s.user_id = _user_id
        )
      )
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
alter table public.pending_friend_invites enable row level security;
alter table public.pending_group_members enable row level security;
alter table public.pending_splits enable row level security;
alter table public.expense_audit_log enable row level security;

-- Profiles
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

-- Groups: creator can read before any group_members row exists
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

-- Expenses (participant = member OR payer OR on a split)
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

create policy "expenses_update_participant"
  on public.expenses for update
  to authenticated
  using (public.can_manage_expense(id, auth.uid()))
  with check (public.can_manage_expense(id, auth.uid()));

create policy "expenses_delete_participant"
  on public.expenses for delete
  to authenticated
  using (public.can_manage_expense(id, auth.uid()));

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

-- Pending friend invites
create policy "pending_friend_invites_select_own"
  on public.pending_friend_invites for select
  to authenticated
  using (inviter_id = auth.uid());

create policy "pending_friend_invites_insert_own"
  on public.pending_friend_invites for insert
  to authenticated
  with check (inviter_id = auth.uid());

create policy "pending_friend_invites_update_own"
  on public.pending_friend_invites for update
  to authenticated
  using (inviter_id = auth.uid())
  with check (inviter_id = auth.uid());

create policy "pending_friend_invites_select_group_member"
  on public.pending_friend_invites for select
  to authenticated
  using (
    inviter_id = auth.uid()
    or exists (
      select 1
      from public.pending_group_members pgm
      where pgm.pending_invite_id = id
        and public.is_group_member(pgm.group_id, auth.uid())
    )
  );

-- Pending group members
create policy "pending_group_members_select_member"
  on public.pending_group_members for select
  to authenticated
  using (public.is_group_member(group_id, auth.uid()));

create policy "pending_group_members_insert_member"
  on public.pending_group_members for insert
  to authenticated
  with check (
    public.is_group_member(group_id, auth.uid())
    and added_by = auth.uid()
  );

create policy "pending_group_members_delete_member"
  on public.pending_group_members for delete
  to authenticated
  using (public.is_group_member(group_id, auth.uid()));

-- Pending splits
create policy "pending_splits_select_member"
  on public.pending_splits for select
  to authenticated
  using (
    exists (
      select 1
      from public.expenses e
      where e.id = expense_id and public.is_group_member(e.group_id, auth.uid())
    )
  );

create policy "pending_splits_insert_member"
  on public.pending_splits for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.expenses e
      where e.id = expense_id and public.is_group_member(e.group_id, auth.uid())
    )
  );

create policy "pending_splits_update_member"
  on public.pending_splits for update
  to authenticated
  using (
    exists (
      select 1
      from public.expenses e
      where e.id = expense_id and public.is_group_member(e.group_id, auth.uid())
    )
  );

create policy "pending_splits_delete_member"
  on public.pending_splits for delete
  to authenticated
  using (
    exists (
      select 1
      from public.expenses e
      where e.id = expense_id and public.is_group_member(e.group_id, auth.uid())
    )
  );

-- Expense audit log (no direct client writes; triggers use SECURITY DEFINER)
create policy "expense_audit_log_select_member"
  on public.expense_audit_log for select
  to authenticated
  using (public.is_group_member(group_id, auth.uid()));

grant select on public.expense_audit_log to authenticated;

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

-- ---------------------------------------------------------------------------
-- Audit triggers: expenses
-- ---------------------------------------------------------------------------

create or replace function public.log_expense_row_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_diff jsonb := '{}'::jsonb;
begin
  if tg_op = 'UPDATE' then
    if row (old.*) is distinct from row (new.*) then
      if old.amount is distinct from new.amount then
        v_diff := v_diff || jsonb_build_object(
          'amount',
          jsonb_build_object('from', old.amount, 'to', new.amount)
        );
      end if;
      if old.paid_by is distinct from new.paid_by then
        v_diff := v_diff || jsonb_build_object(
          'paid_by',
          jsonb_build_object('from', old.paid_by, 'to', new.paid_by)
        );
      end if;
      if old.description is distinct from new.description then
        v_diff := v_diff || jsonb_build_object(
          'description',
          jsonb_build_object('from', old.description, 'to', new.description)
        );
      end if;
      if old.expense_date is distinct from new.expense_date then
        v_diff := v_diff || jsonb_build_object(
          'expense_date',
          jsonb_build_object('from', old.expense_date, 'to', new.expense_date)
        );
      end if;
      if old.group_id is distinct from new.group_id then
        v_diff := v_diff || jsonb_build_object(
          'group_id',
          jsonb_build_object('from', old.group_id, 'to', new.group_id)
        );
      end if;
      if v_diff <> '{}'::jsonb then
        insert into public.expense_audit_log (group_id, expense_id, actor_id, action, details)
        values (
          new.group_id,
          new.id,
          auth.uid(),
          'expense_updated',
          jsonb_build_object('changes', v_diff)
        );
      end if;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    insert into public.expense_audit_log (group_id, expense_id, actor_id, action, details)
    values (
      old.group_id,
      old.id,
      auth.uid(),
      'expense_deleted',
      jsonb_build_object('expense', row_to_json(old)::jsonb)
    );
    return old;
  end if;
  return coalesce(new, old);
end;
$$;

create trigger expenses_audit_update
  after update on public.expenses
  for each row
  execute function public.log_expense_row_audit();

create trigger expenses_audit_delete
  before delete on public.expenses
  for each row
  execute function public.log_expense_row_audit();

-- ---------------------------------------------------------------------------
-- Audit triggers: splits (including pending_splits)
-- ---------------------------------------------------------------------------

create or replace function public.log_splits_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense_id uuid;
  v_group_id uuid;
  v_payload jsonb;
begin
  v_expense_id := coalesce(new.expense_id, old.expense_id);
  v_group_id := (
    select e.group_id
    from public.expenses e
    where e.id = v_expense_id
    limit 1
  );

  if v_group_id is null then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    v_payload := jsonb_build_object(
      'target',
      tg_table_name,
      'op',
      'insert',
      'row',
      row_to_json(new)::jsonb
    );
  elsif tg_op = 'UPDATE' then
    v_payload := jsonb_build_object(
      'target',
      tg_table_name,
      'op',
      'update',
      'old',
      row_to_json(old)::jsonb,
      'new',
      row_to_json(new)::jsonb
    );
  elsif tg_op = 'DELETE' then
    v_payload := jsonb_build_object(
      'target',
      tg_table_name,
      'op',
      'delete',
      'row',
      row_to_json(old)::jsonb
    );
  end if;

  insert into public.expense_audit_log (group_id, expense_id, actor_id, action, details)
  values (v_group_id, v_expense_id, auth.uid(), 'splits_changed', v_payload);

  return coalesce(new, old);
end;
$$;

create trigger splits_audit_insert
  after insert on public.splits
  for each row
  execute function public.log_splits_audit();

create trigger splits_audit_update
  after update on public.splits
  for each row
  execute function public.log_splits_audit();

create trigger splits_audit_delete
  after delete on public.splits
  for each row
  execute function public.log_splits_audit();

create trigger pending_splits_audit_insert
  after insert on public.pending_splits
  for each row
  execute function public.log_splits_audit();

create trigger pending_splits_audit_update
  after update on public.pending_splits
  for each row
  execute function public.log_splits_audit();

create trigger pending_splits_audit_delete
  after delete on public.pending_splits
  for each row
  execute function public.log_splits_audit();
