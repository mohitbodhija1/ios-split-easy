-- Fix: creators could not SELECT a group they just inserted until group_members existed.
-- That broke PostgREST insert(...).select() and the EXISTS(...) in group_members_insert.

drop policy if exists "groups_select_member" on public.groups;

create policy "groups_select_member"
  on public.groups for select
  to authenticated
  using (
    created_by = auth.uid()
    or public.is_group_member(id, auth.uid())
  );
