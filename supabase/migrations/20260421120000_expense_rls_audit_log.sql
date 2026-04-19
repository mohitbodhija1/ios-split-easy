-- Broader expense update/delete: group member OR payer OR someone on a split for that expense.
-- Audit trail for expense edits, deletions, and split changes (settle-up / split edits).

-- ---------------------------------------------------------------------------
-- Who may change an expense row
-- ---------------------------------------------------------------------------
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

drop policy if exists "expenses_update_member" on public.expenses;
create policy "expenses_update_participant"
  on public.expenses for update
  to authenticated
  using (public.can_manage_expense(id, auth.uid()))
  with check (public.can_manage_expense(id, auth.uid()));

drop policy if exists "expenses_delete_payer_or_creator" on public.expenses;
create policy "expenses_delete_participant"
  on public.expenses for delete
  to authenticated
  using (public.can_manage_expense(id, auth.uid()));

-- ---------------------------------------------------------------------------
-- Audit log (group_id kept so rows stay readable after expense delete)
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

create index idx_expense_audit_log_group_created
  on public.expense_audit_log (group_id, created_at desc);

create index idx_expense_audit_log_expense_created
  on public.expense_audit_log (expense_id, created_at desc);

alter table public.expense_audit_log enable row level security;

create policy "expense_audit_log_select_member"
  on public.expense_audit_log for select
  to authenticated
  using (public.is_group_member(group_id, auth.uid()));

-- No direct client writes; triggers use SECURITY DEFINER.

grant select on public.expense_audit_log to authenticated;

-- ---------------------------------------------------------------------------
-- Triggers: expenses
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
-- Triggers: splits (settle-up / adjustments)
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
