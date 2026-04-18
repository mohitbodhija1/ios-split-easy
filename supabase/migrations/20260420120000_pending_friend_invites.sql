-- Shadow-user pending friend invites

create table if not exists public.pending_friend_invites (
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

create index if not exists idx_pending_friend_invites_inviter
  on public.pending_friend_invites (inviter_id, status, created_at desc);

alter table public.pending_friend_invites enable row level security;

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
