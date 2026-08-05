# Plugin context

## Purpose

Expose supported OpenBSP operations through the plugin and MCP tools while
preserving the same organization authorization and contracts as the API.

## Boundaries

- The plugin is a consumer of OpenBSP interfaces, not an alternative database
  access path.
- It must not expose secrets, service-role credentials, raw tracking tokens, or
  data from unauthorized organizations.
- Changes to messaging or tracking contracts require their respective context
  documentation and ADRs to be consulted.

## Sources

- `plugin/`
- `supabase/functions/mcp/`
