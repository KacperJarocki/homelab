# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The repo's agent instructions (layout, sync waves, Argo CD conventions, secrets and gotchas) live in AGENTS.md and are the primary reference:

@AGENTS.md

## Additions to AGENTS.md

### CI
- `.github/workflows/validate.yml` runs `scripts/validate-local.sh` on every PR and on pushes to `main`. Run it locally before pushing.
  - If OCI charts (ARC from ghcr.io) fail locally with `docker-credential-desktop: executable file not found`, run it with an empty Docker config: `DOCKER_CONFIG=$(mktemp -d) scripts/validate-local.sh`.
- `.github/workflows/kubescape.yml` `images` job (PRs only): fails if an image the PR adds or bumps has a critical CVE that the image it replaces did not have. Check a bump before committing with `scripts/image-cve-gate.sh` (usage in AGENTS.md).
- Renovate (`renovate.json`) uses three managers. `argocd` tracks chart versions in `argocd/root/`. `kubernetes` tracks `image:` refs in `infra/` and `apps/` manifests. `helm-values` tracks image overrides in `values.yaml`, but only when `repository` (optionally `registry`) sits next to `tag`; a bare `tag:` override is never updated.
- `.github/workflows/opnsense.yml`: PRs that touch `network/opnsense/**` only run `tofu fmt -check` and `tofu validate` on `ubuntu-latest` (no credentials). A push to `main` runs `plan` on `homelab-arm64`. Only when the plan has changes does it run backup + `apply` of exactly that plan, gated by the `opnsense` environment, which needs manual approval.
  - A plan that deletes or replaces any OPNsense object fails on purpose. If the delete is intended, re-run via `workflow_dispatch` on `main` with `allow_destroy=true`. To stop managing an object without deleting it, use a `removed` block with `destroy = false`.
- `.github/workflows/release.yml` runs GitVersion. Commit messages use Conventional Commit prefixes (`feat(scope):`, `fix(scope):`, `chore(scope):`) because they drive the version bump.

### OpenTofu (`network/opnsense`)
- Offline checks: `cd network/opnsense && tofu fmt -check -recursive -diff && tofu init -backend=false -input=false && tofu validate` (same as CI).
- A real `plan` from a workstation needs a RustFS port-forward and the `opnsense-tofu` Secret exported as env vars; the exact snippet is in `network/opnsense/README.md` ("The S3 API of RustFS is cluster-internal…").
- After changing providers, update the lock file for every platform with `tofu providers lock -platform=linux_arm64 -platform=linux_amd64 -platform=darwin_arm64`.
- Rules of thumb from the README: adopt before you add (import what exists, reach an empty plan, then change). The anti-lockout rule and the LAN -> GUI/SSH rules stay out of OpenTofu. One concern per PR.

### Adding a component
1. Create `apps/<ns>/<name>/values.yaml` for a workload, or `infra/<name>/values.yaml` for a platform component. Add a `manifests/` dir next to it if needed.
2. Add `argocd/root/apps/<name>.yaml` or `argocd/root/infra/<name>.yaml`; copying a neighbour is easiest. Use the two-source pattern: the chart from its Helm repo, plus this repo with `ref: values` (see README.md). Set a sync wave.
3. Add a new Helm repo URL to the `sourceRepos` of the matching AppProject in `argocd/root/projects/`.
4. Run `scripts/validate-local.sh`.

### Bootstrap
- Fresh cluster or disaster recovery: `scripts/bootstrap-argocd.sh`. Create the out-of-Git Secrets first with the matching `scripts/create-*-secrets.sh` (AGENTS.md says which component needs which).
