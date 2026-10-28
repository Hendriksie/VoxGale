# Tasks

## 1. Dependabot configuration

- [x] 1.1 Add `.github/dependabot.yml`: weekly version updates for the
  `pub` ecosystem (directory `/`, pub.dev is the default registry) and the
  `github-actions` ecosystem (directory `/`), both with
  `open-pull-requests-limit: 5`; header comment explains that Dependabot
  security alerts are a repository setting, not configurable here. (Verified: file created.)
- [x] 1.2 Validate the YAML parses. (Verified: parses; 2 update jobs — pub, github-actions.)

## 2. Repository settings (user steps)

- [x] 2.1 Enable **Dependabot alerts**: Settings → Security & analysis →
  "Dependabot alerts". (Free; surfaces pub dependency-graph
  vulnerabilities on the Security tab.) (Verified 2026-10-28: user enabled it. End-to-end proof: Dependabot already opened PRs #1 (checkout 6→7) and #2 (setup-java 5→6) from the new dependabot.yml.)
- [ ] 2.2 Optionally enable **Dependabot security updates** (same page) to
  get automatic fix PRs for vulnerable dependencies.

## 3. Validation

- [x] 3.1 Run `openspec validate 2026-10-28-dependabot --strict`. (Verified: change valid; skip_specs accepted with zero deltas.)
- [x] 3.2 Commit and push; the first Dependabot PR (if any update is
  already due) landing green in CI verifies the setup end-to-end. (Verified: committed and pushed.)

## Workflow follow-up

- Review with the user; archive after the settings are enabled and the
  change is reviewed.
