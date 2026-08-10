# Security Policy

## Reporting a vulnerability

**Do not open a public issue for security reports.**

Report vulnerabilities privately to the maintainer:

- GitHub: [@cristianoaredes](https://github.com/cristianoaredes) — use
  [private vulnerability reporting](https://github.com/cristianoaredes/foundationmodels-dart/security/advisories/new)
  on this repository.

Include: affected package/version, reproduction path, and impact. You will
receive an acknowledgement; fixes are coordinated before public disclosure.

## Scope notes

This project is a client-side bridge to on-device Apple Foundation Models.
The security-relevant invariants (see `CONTINUATION.md` §6):

- **No silent cloud fallback** — the mock never phones home; the Apple
  provider stays on device.
- **`instructions` is a trusted channel** — never carry user input, tool
  results, or retrieved content.
- **Image paths are fail-closed** — rejected unless under
  `allowedImageRoots` (symlink-aware, upstream core).
- **Errors never leak raw model content** — `rawContent` and refusal
  transcripts are never forwarded across the channel.
- **Secrets** — tokens (e.g. daemon `authToken` in the phase-5 desktop
  transport) are never logged.

If you find a way to violate any of these, that is in scope for a report.

## Supported versions

Pre-1.0: only the latest commit on `main` receives fixes.

## License

AGPL-3.0-only — see [`LICENSE`](LICENSE).
