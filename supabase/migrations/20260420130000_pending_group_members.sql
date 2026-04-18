-- Allow adding pending (shadow) friends to groups before signup

create table if not exists public.pending_group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  pending_invite_id uuid not null references public.pending_friend_invites (id) on delete cascade,
  added_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (group_id, pending_invite_id)
);

create index if not exists idx_pending_group_members_group
  on public.pending_group_members (group_id, created_at desc);

alter table public.pending_group_members enable row level security;

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

-- Group members can view invites that were attached to their groups.
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
