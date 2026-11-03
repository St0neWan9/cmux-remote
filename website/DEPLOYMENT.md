# Production deployment receipt

- Hostname: `cmux-remote.trentaml.com`.
- Worker: `cmux-remote-website`.
- Version: `d5da2b6f-c5a9-403e-a927-871dd6711e42`.
- Backup: `https://cmux-remote-website.cmux-remote-relay.workers.dev`.
- Custom Domain enabled in production under the account owning `trentaml.com`.

The new page is now the sole landing-page source: `/` defaults to English and
`/zh/` serves Simplified Chinese. Superseded v2 source, duplicated assets, and
the separate production build/configuration were removed. The former `/v2/`
and `/v2/zh/` paths have no compatibility routes and return 404.

Deployment uses `npm run deploy` and the existing local Wrangler OAuth login.
No API token or other credential is committed. Cloudflare owns the Custom
Domain DNS and certificate lifecycle. This is an independent Cloudflare Worker,
not a Codex Site or an accountless preview tunnel.

## Verification

The final build and Wrangler dry-run passed before deployment. Cloudflare
confirmed the uploaded version and domain binding. Public DNS resolved the
hostname to Cloudflare. HTTPS with certificate and hostname verification against
those public DNS addresses returned the expected new English and Chinese pages,
styles and language script (200). Unknown URLs and README remained real 404
responses. The initial deployment's v2 redirects were subsequently removed at
the user's request; the current release serves only the canonical landing pages.

The published workers.dev site opened in Chrome and switched from English to
Chinese under `/zh/`. Initial custom-domain requests failed on some client
connections while requests to publicly resolved Cloudflare addresses succeeded.
Subsequent external TLS checks passed for all four public IPv4/IPv6 addresses,
and repeated requests over the previously failing proxy route returned 200 with
certificate verification enabled. The user also confirmed mobile access had
recovered. No deployment or network configuration changed during diagnosis;
the exact cause of the transient failure was not established. Keep the backup
address available as an independent hostname for troubleshooting.

Republish with `npm run deploy`; use `npm run deploy:dry-run` for packaging only.
