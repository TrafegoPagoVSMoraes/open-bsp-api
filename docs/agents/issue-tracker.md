# Issue tracker: GitHub

Issues and PRDs for this repository live in GitHub Issues at
`TrafegoPagoVSMoraes/open-bsp-api`. Use the `gh` CLI from this clone and pass
`--repo TrafegoPagoVSMoraes/open-bsp-api` when repository inference is
ambiguous.

## Conventions

- Create: `gh issue create --repo TrafegoPagoVSMoraes/open-bsp-api`.
- Read:
  `gh issue view <number> --repo TrafegoPagoVSMoraes/open-bsp-api --comments`.
- List: `gh issue list --repo TrafegoPagoVSMoraes/open-bsp-api --state open`.
- Comment: `gh issue comment <number> --repo TrafegoPagoVSMoraes/open-bsp-api`.
- Close: `gh issue close <number> --repo TrafegoPagoVSMoraes/open-bsp-api`.

Use issue bodies for acceptance criteria, constraints, validation evidence, and
links to relevant ADRs. Never include tokens, credentials, `.env` values, raw
contact data, or production logs containing personal data.

## Pull requests as a request surface

**PRs as a request surface: no.** Pull requests implement approved work; they
are not treated as incoming feature requests by triage workflows.

## Skill vocabulary

- "Publish to the issue tracker" means create a GitHub issue in this repo.
- "Fetch the relevant ticket" means read the GitHub issue and its comments.
