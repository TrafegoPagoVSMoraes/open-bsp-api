-- Preserve explicit project-contact provenance for direct/manual writes.
create or replace function public.sync_explicit_project_contact_origin()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.source <> 'tag' then
    insert into public.project_contact_origins (
      organization_id, project_id, contact_id, source, source_key
    ) values (
      new.organization_id, new.project_id, new.contact_id, new.source, ''
    ) on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger sync_explicit_project_contact_origin
after insert or update of source on public.project_contacts
for each row execute function public.sync_explicit_project_contact_origin();
