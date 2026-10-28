// Shot Link share service — Cloudflare Worker + R2.
//
// POST   /v1/uploads                  reserve an ID → { id, url, uploadURL, deleteToken, expiresAt }
// PUT    /v1/uploads/:id/content?t=…  upload the image bytes (one time, within 5 minutes)
// DELETE /v1/uploads/:id              Authorization: Bearer <deleteToken>
// GET    /:id                         share page (og:image, download, report link)
// GET    /:id/raw                     the image itself
//
// R2 layout: meta/<id>.json holds hashed tokens + expiry; img/<id> holds the bytes.

const MAX_BYTES = 10 * 1024 * 1024;
const RESERVATION_TTL_MS = 5 * 60 * 1000;
const ALLOWED_TYPES = new Set(["image/png", "image/jpeg", "image/gif", "image/webp"]);
const ALLOWED_EXPIRY = new Set([86400, 604800, 2592000, null]);
const ID_PATTERN = /^[0-9A-Za-z]{16}$/;
const BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (err) {
      console.error(err);
      return json({ error: "internal_error" }, 500);
    }
  },

  async scheduled(_event, env) {
    await sweep(env);
  },
};

async function route(request, env) {
  const url = new URL(request.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const method = request.method;

  if (method === "POST" && url.pathname === "/v1/uploads") return reserve(request, env, url);
  if (method === "PUT" && parts.length === 4 && parts[0] === "v1" && parts[1] === "uploads" && parts[3] === "content") {
    return receive(request, env, parts[2], url.searchParams.get("t"));
  }
  if (method === "DELETE" && parts.length === 3 && parts[0] === "v1" && parts[1] === "uploads") {
    return remove(request, env, parts[2]);
  }
  if (method === "GET" || method === "HEAD") {
    if (parts.length === 0) return new Response("Shot Link", { headers: { "content-type": "text/plain" } });
    if (parts.length === 1) return sharePage(env, url, parts[0]);
    if (parts.length === 2 && parts[1] === "raw") return rawImage(env, parts[0], url.searchParams.has("download"));
  }
  return json({ error: "not_found" }, 404);
}

// MARK: - Upload

async function reserve(request, env, url) {
  const installID = request.headers.get("x-install-id") || "";
  if (!/^[0-9a-f-]{36}$/i.test(installID)) return json({ error: "missing_install_id" }, 400);

  if (env.UPLOAD_LIMITER) {
    const ip = request.headers.get("cf-connecting-ip") || "unknown";
    const [byInstall, byIP] = await Promise.all([
      env.UPLOAD_LIMITER.limit({ key: `install:${installID}` }),
      env.UPLOAD_LIMITER.limit({ key: `ip:${ip}` }),
    ]);
    if (!byInstall.success || !byIP.success) return json({ error: "rate_limited" }, 429);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const size = Number(body.size);
  const contentType = String(body.contentType || "");
  const expiresIn = body.expiresIn ?? null;
  if (!Number.isInteger(size) || size <= 0 || size > MAX_BYTES) return json({ error: "too_large", maxBytes: MAX_BYTES }, 413);
  if (!ALLOWED_TYPES.has(contentType)) return json({ error: "unsupported_type" }, 415);
  if (!ALLOWED_EXPIRY.has(expiresIn)) return json({ error: "invalid_expiry" }, 400);

  const id = randomID(16);
  const deleteToken = randomToken();
  const uploadToken = randomToken();
  const now = Date.now();
  const meta = {
    id,
    state: "pending",
    size,
    contentType,
    createdAt: new Date(now).toISOString(),
    reservedUntil: now + RESERVATION_TTL_MS,
    expiresAt: expiresIn === null ? null : new Date(now + expiresIn * 1000).toISOString(),
    deleteHash: await sha256(deleteToken),
    uploadHash: await sha256(uploadToken),
  };
  await env.BUCKET.put(`meta/${id}.json`, JSON.stringify(meta), { httpMetadata: { contentType: "application/json" } });

  const origin = url.origin;
  return json(
    {
      id,
      url: `${origin}/${id}`,
      uploadURL: `${origin}/v1/uploads/${id}/content?t=${uploadToken}`,
      deleteToken,
      expiresAt: meta.expiresAt,
    },
    201,
  );
}

async function receive(request, env, id, token) {
  if (!ID_PATTERN.test(id) || !token) return json({ error: "not_found" }, 404);
  const meta = await readMeta(env, id);
  if (!meta || meta.state !== "pending") return json({ error: "not_found" }, 404);
  if (!(await tokenMatches(token, meta.uploadHash))) return json({ error: "forbidden" }, 403);
  if (Date.now() > meta.reservedUntil) return json({ error: "reservation_expired" }, 410);
  if ((request.headers.get("content-type") || "") !== meta.contentType) return json({ error: "type_mismatch" }, 415);

  const declared = Number(request.headers.get("content-length"));
  if (!Number.isFinite(declared) || declared !== meta.size) return json({ error: "size_mismatch" }, 400);

  const object = await env.BUCKET.put(`img/${id}`, request.body, {
    httpMetadata: { contentType: meta.contentType },
    customMetadata: { expiresAt: meta.expiresAt || "" },
  });
  if (!object || object.size !== meta.size) {
    await env.BUCKET.delete(`img/${id}`);
    return json({ error: "size_mismatch" }, 400);
  }

  meta.state = "ready";
  delete meta.uploadHash;
  delete meta.reservedUntil;
  await env.BUCKET.put(`meta/${id}.json`, JSON.stringify(meta));
  return json({ id }, 200);
}

async function remove(request, env, id) {
  if (!ID_PATTERN.test(id)) return json({ error: "not_found" }, 404);
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  const meta = await readMeta(env, id);
  if (!meta) return json({ error: "not_found" }, 404);
  if (!token || !(await tokenMatches(token, meta.deleteHash))) return json({ error: "forbidden" }, 403);
  await env.BUCKET.delete([`img/${id}`, `meta/${id}.json`]);
  return new Response(null, { status: 204 });
}

// MARK: - Viewing

async function liveMeta(env, id) {
  if (!ID_PATTERN.test(id)) return null;
  const meta = await readMeta(env, id);
  if (!meta || meta.state !== "ready") return null;
  if (meta.expiresAt && Date.parse(meta.expiresAt) < Date.now()) return null;
  return meta;
}

async function rawImage(env, id, download) {
  const meta = await liveMeta(env, id);
  if (!meta) return notFoundPage();
  const object = await env.BUCKET.get(`img/${id}`);
  if (!object) return notFoundPage();
  const ext = meta.contentType.split("/")[1].replace("jpeg", "jpg");
  const headers = new Headers({
    "content-type": meta.contentType,
    "cache-control": "public, max-age=300",
    "x-content-type-options": "nosniff",
    "content-security-policy": "default-src 'none'",
  });
  if (download) headers.set("content-disposition", `attachment; filename="screenshot-${id}.${ext}"`);
  return new Response(object.body, { headers });
}

async function sharePage(env, url, id) {
  const meta = await liveMeta(env, id);
  if (!meta) return notFoundPage();
  const image = `${url.origin}/${id}/raw`;
  const report = `mailto:${env.ABUSE_EMAIL || "abuse@example.com"}?subject=${encodeURIComponent(`Report ${url.origin}/${id}`)}`;
  const expires = meta.expiresAt ? `Expires ${new Date(meta.expiresAt).toUTCString()}` : "No expiry";
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Screenshot</title>
<meta property="og:type" content="website">
<meta property="og:title" content="Screenshot">
<meta property="og:image" content="${image}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:image" content="${image}">
<style>
  :root { --bg: #f5f5f7; --fg: #1d1d1f; --muted: #6e6e73; --card: #fff; --line: rgba(0,0,0,.08); --accent: #5b5bff; }
  @media (prefers-color-scheme: dark) { :root { --bg: #0e0e12; --fg: #f5f5f7; --muted: #a1a1aa; --card: #18181d; --line: rgba(255,255,255,.12); } }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; background: var(--bg); color: var(--fg); font: 14px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; display: flex; flex-direction: column; align-items: center; padding: 24px 16px; gap: 16px; }
  figure { margin: 0; max-width: min(1400px, 100%); background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 12px; box-shadow: 0 20px 60px rgba(0,0,0,.18); }
  img { display: block; max-width: 100%; height: auto; border-radius: 10px; }
  nav { display: flex; gap: 12px; align-items: center; flex-wrap: wrap; justify-content: center; color: var(--muted); }
  a.button { color: #fff; background: linear-gradient(90deg, #5b5bff, #22d3ee); padding: 8px 16px; border-radius: 999px; text-decoration: none; font-weight: 600; }
  a.muted { color: var(--muted); }
</style>
</head>
<body>
<figure><img src="${image}" alt="Shared screenshot"></figure>
<nav>
  <a class="button" href="${image}?download">Download</a>
  <span>${expires}</span>
  <a class="muted" href="${report}">Report abuse</a>
</nav>
</body>
</html>`;
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=60",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      "content-security-policy": "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'",
    },
  });
}

function notFoundPage() {
  return new Response("This screenshot doesn't exist, expired, or was deleted.", {
    status: 404,
    headers: { "content-type": "text/plain; charset=utf-8" },
  });
}

// MARK: - Cleanup

async function sweep(env) {
  const now = Date.now();
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix: "meta/", cursor });
    for (const entry of page.objects) {
      const object = await env.BUCKET.get(entry.key);
      if (!object) continue;
      const meta = await object.json();
      const expired = meta.expiresAt && Date.parse(meta.expiresAt) < now;
      const abandoned = meta.state === "pending" && now > meta.reservedUntil + 60 * 60 * 1000;
      if (expired || abandoned) {
        await env.BUCKET.delete([`img/${meta.id}`, entry.key]);
      }
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
}

// MARK: - Helpers

async function readMeta(env, id) {
  const object = await env.BUCKET.get(`meta/${id}.json`);
  return object ? object.json() : null;
}

function randomID(length) {
  let out = "";
  while (out.length < length) {
    const bytes = crypto.getRandomValues(new Uint8Array(length * 2));
    for (const b of bytes) {
      if (b < 248 && out.length < length) out += BASE62[b % 62];
    }
  }
  return out;
}

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function tokenMatches(token, expectedHash) {
  if (!expectedHash) return false;
  const actual = await sha256(token);
  if (actual.length !== expectedHash.length) return false;
  let diff = 0;
  for (let i = 0; i < actual.length; i++) diff |= actual.charCodeAt(i) ^ expectedHash.charCodeAt(i);
  return diff === 0;
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}
