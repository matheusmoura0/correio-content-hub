# Project Workflow

- Do not run the application, databases, development servers, builds, or manual
  or automated application tests locally. The user requires deployment and
  functional validation on the VPS.
- Static code review, syntax checks, and Git diff checks are allowed.
- Prepare changes for the existing VPS deployment at `/opt/correio-content-hub`
  with `compose.production.yml` and `.env.production`. Never expose environment
  secrets in output or commits.
- Explain required migrations and any verification that remains for the VPS.
