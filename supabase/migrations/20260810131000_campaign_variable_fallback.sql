-- A scheduled TAG audience is materialized later in PostgreSQL. Keep its
-- variable fallback consistent with campaign-management so an incomplete
-- contact record cannot make the whole audience disappear at send time.
create or replace function public.resolve_campaign_contact_variables(
  p_mapping jsonb,
  p_name text
) returns jsonb
language sql immutable set search_path = '' as $$
  with values_resolved as (
    select entry.key,
      case entry.value->>'source'
        when 'constant' then entry.value->>'constant'
        when 'first_name' then coalesce(
          nullif(split_part(btrim(coalesce(p_name, '')), ' ', 1), ''),
          'Você'
        )
        when 'full_name' then coalesce(nullif(btrim(coalesce(p_name, '')), ''), 'Você')
        else null
      end as value
    from jsonb_each(coalesce(p_mapping, '{}'::jsonb)) entry
  )
  select case
    when exists (select 1 from values_resolved where nullif(btrim(value), '') is null)
      then null
    else coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  end
  from values_resolved;
$$;

revoke all on function public.resolve_campaign_contact_variables(jsonb, text)
from public, anon, authenticated;
grant execute on function public.resolve_campaign_contact_variables(jsonb, text)
to service_role;
