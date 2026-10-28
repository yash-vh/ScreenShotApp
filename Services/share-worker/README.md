# Shot Link share service

The free upload backend used by the app's **Free Share Link** storage mode: a Cloudflare Worker in front of an R2 bucket.

- Unguessable 16-character base62 IDs (never sequential).
- Delete tokens are returned once and stored server-side only as SHA-256 hashes; the app keeps them in the Keychain.
- Expiry of 1 / 7 / 30 days or none, enforced on read and swept daily by a cron trigger.
- 10 MB limit, PNG / JPEG / GIF / WebP only, per-install and per-IP rate limiting.
- Share pages are `noindex`, send no referrer, and carry a report-abuse link.

## Deploy

```bash
cd Services/share-worker
npx wrangler login
npx wrangler r2 bucket create shotlink-uploads
# edit ABUSE_EMAIL in wrangler.toml, then:
npx wrangler deploy
```

Attach a custom domain to the Worker (Workers → your worker → Settings → Domains), then paste
`https://<that-domain>` into **Settings › Storage & Cloud › Free Share Link › Service URL** in the app.

## API

| Method | Path | Notes |
|---|---|---|
| `POST` | `/v1/uploads` | Header `X-Install-ID`; body `{ size, contentType, expiresIn }` (`expiresIn`: 86400, 604800, 2592000 or `null`). Returns `{ id, url, uploadURL, deleteToken, expiresAt }`. |
| `PUT` | `/v1/uploads/:id/content?t=…` | Raw bytes; `Content-Type` and length must match the reservation; valid for 5 minutes. |
| `DELETE` | `/v1/uploads/:id` | `Authorization: Bearer <deleteToken>`. |
| `GET` | `/:id` | Share page with `og:image`. |
| `GET` | `/:id/raw` | The image (`?download` for an attachment). |

## Before going public

Check Cloudflare's current free-tier limits, publish Terms and a Privacy page, and set up a takedown process for the abuse address.
