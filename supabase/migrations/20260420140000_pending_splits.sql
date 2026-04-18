-- Pending splits for shadow/pending members

create table if not exists public.pending_splits (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses (id) on delete cascade,
  pending_invite_id uuid not null references public.pending_friend_invites (id) on delete cascade,
  amount_owed numeric(14, 2) not null check (amount_owed >= 0),
  unique (expense_id, pending_invite_id)
);

create index if not exists idx_pending_splits_expense on public.pending_splits (expense_id);

alter table public.pending_splits enable row level security;

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
