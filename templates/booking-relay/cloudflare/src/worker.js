const MAX_BODY_BYTES = 16 * 1024;
const DEFAULT_RETENTION_SECONDS = 7 * 24 * 60 * 60;
const DEFAULT_MAX_PENDING = 100;
const DEFAULT_IP_LIMIT = 30;
const DEFAULT_INBOX_LIMIT = 60;
const RATE_WINDOW_SECONDS = 60;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") {
      return optionsResponse(request, env);
    }

    if (request.method === "GET" && url.pathname === "/healthz") {
      return json({
        ok: true,
        allowedOrigin: env.ALLOWED_ORIGIN || "",
        storage: "cloudflare-kv",
      }, 200, request, env);
    }

    const inboxMatch = url.pathname.match(/^\/v1\/inboxes\/([A-Za-z0-9_-]{3,96})\/requests$/);
    if (inboxMatch && request.method === "POST") {
      return createRequest(request, env, inboxMatch[1]);
    }
    if (inboxMatch && request.method === "GET") {
      return listRequests(request, env, inboxMatch[1], url.searchParams.get("cursor") || undefined);
    }

    const deleteMatch = url.pathname.match(/^\/v1\/inboxes\/([A-Za-z0-9_-]{3,96})\/requests\/([A-Za-z0-9_-]{8,128})$/);
    if (deleteMatch && request.method === "DELETE") {
      return deleteRequest(request, env, deleteMatch[1], deleteMatch[2]);
    }

    return json({ error: "not_found" }, 404, request, env);
  },
};

async function createRequest(request, env, inboxId) {
  const originCheck = assertAllowedOrigin(request, env);
  if (originCheck) return originCheck;

  const contentLength = Number(request.headers.get("content-length") || "0");
  if (contentLength > MAX_BODY_BYTES) {
    return json({ error: "payload_too_large" }, 413, request, env);
  }

  const ip = request.headers.get("cf-connecting-ip") || "unknown";
  const ipRate = await rateLimit(env, `ip:${ip}`, numberEnv(env.IP_RATE_LIMIT, DEFAULT_IP_LIMIT));
  if (!ipRate.ok) return json({ error: "rate_limited" }, 429, request, env);

  const inboxRate = await rateLimit(env, `inbox:${inboxId}`, numberEnv(env.INBOX_RATE_LIMIT, DEFAULT_INBOX_LIMIT));
  if (!inboxRate.ok) return json({ error: "rate_limited" }, 429, request, env);

  let envelope;
  try {
    envelope = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400, request, env);
  }

  const validation = validateEnvelope(envelope, inboxId);
  if (!validation.ok) {
    return json({ error: validation.error }, 400, request, env);
  }

  if (env.TURNSTILE_SECRET_KEY) {
    const turnstile = await verifyTurnstile(env, request, envelope.turnstileToken);
    if (!turnstile) return json({ error: "turnstile_rejected" }, 403, request, env);
  }

  const pendingCount = await countPending(env, inboxId);
  if (pendingCount >= numberEnv(env.MAX_PENDING_REQUESTS, DEFAULT_MAX_PENDING)) {
    return json({ error: "inbox_full" }, 429, request, env);
  }

  const retentionSeconds = numberEnv(env.RETENTION_SECONDS, DEFAULT_RETENTION_SECONDS);
  const key = requestKey(inboxId, envelope.requestID);
  await env.BOOKING_REQUESTS.put(key, JSON.stringify(envelope), {
    expirationTtl: retentionSeconds,
    metadata: { createdAt: envelope.createdAt },
  });

  return json({ ok: true }, 202, request, env);
}

async function listRequests(request, env, inboxId, cursor) {
  const auth = assertAdmin(request, env);
  if (auth) return auth;

  const list = await env.BOOKING_REQUESTS.list({
    prefix: `inbox:${inboxId}:request:`,
    cursor,
    limit: 50,
  });
  const requests = [];
  for (const key of list.keys) {
    const value = await env.BOOKING_REQUESTS.get(key.name, "json");
    if (value) requests.push(value);
  }

  return json({ requests, cursor: list.cursor || null }, 200, request, env);
}

async function deleteRequest(request, env, inboxId, requestId) {
  const auth = assertAdmin(request, env);
  if (auth) return auth;

  await env.BOOKING_REQUESTS.delete(requestKey(inboxId, requestId));
  return json({ ok: true }, 200, request, env);
}

function validateEnvelope(envelope, inboxId) {
  if (!envelope || typeof envelope !== "object") return { ok: false, error: "invalid_envelope" };
  if (envelope.schemaVersion !== 1) return { ok: false, error: "invalid_schema" };
  if (envelope.inboxID !== inboxId) return { ok: false, error: "wrong_inbox" };
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(envelope.requestID || "")) return { ok: false, error: "invalid_request_id" };
  if (!/^[A-Za-z0-9_-]{3,96}$/.test(envelope.shareID || "")) return { ok: false, error: "invalid_share_id" };
  if (typeof envelope.ciphertext !== "string" || envelope.ciphertext.length > MAX_BODY_BYTES) return { ok: false, error: "invalid_ciphertext" };
  if (typeof envelope.nonce !== "string" || envelope.nonce.length < 16) return { ok: false, error: "invalid_nonce" };
  if (typeof envelope.algorithm !== "string" || !envelope.algorithm.includes("AES-GCM")) return { ok: false, error: "invalid_algorithm" };
  return { ok: true };
}

async function rateLimit(env, key, limit) {
  const counterKey = `rate:${key}:${Math.floor(Date.now() / (RATE_WINDOW_SECONDS * 1000))}`;
  const current = Number((await env.BOOKING_REQUESTS.get(counterKey)) || "0");
  if (current >= limit) {
    return { ok: false };
  }
  await env.BOOKING_REQUESTS.put(counterKey, String(current + 1), { expirationTtl: RATE_WINDOW_SECONDS * 2 });
  return { ok: true };
}

async function countPending(env, inboxId) {
  const list = await env.BOOKING_REQUESTS.list({
    prefix: `inbox:${inboxId}:request:`,
    limit: DEFAULT_MAX_PENDING + 1,
  });
  return list.keys.length;
}

async function verifyTurnstile(env, request, token) {
  if (!token) return false;
  const formData = new FormData();
  formData.append("secret", env.TURNSTILE_SECRET_KEY);
  formData.append("response", token);
  const ip = request.headers.get("cf-connecting-ip");
  if (ip) formData.append("remoteip", ip);

  const response = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    body: formData,
  });
  const result = await response.json();
  return result.success === true;
}

function requestKey(inboxId, requestId) {
  return `inbox:${inboxId}:request:${requestId}`;
}

function assertAdmin(request, env) {
  const token = env.INBOX_ADMIN_TOKEN || "";
  const authorization = request.headers.get("authorization") || "";
  if (!token || authorization !== `Bearer ${token}`) {
    return json({ error: "unauthorized" }, 401, request, env);
  }
  return null;
}

function assertAllowedOrigin(request, env) {
  const allowedOrigin = env.ALLOWED_ORIGIN || "";
  const origin = request.headers.get("origin") || "";
  if (!allowedOrigin || origin !== allowedOrigin) {
    return json({ error: "origin_not_allowed" }, 403, request, env);
  }
  return null;
}

function optionsResponse(request, env) {
  return new Response(null, {
    status: 204,
    headers: corsHeaders(request, env),
  });
}

function json(body, status, request, env) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      ...corsHeaders(request, env),
    },
  });
}

function corsHeaders(request, env) {
  const origin = request.headers.get("origin") || "";
  const allowedOrigin = env.ALLOWED_ORIGIN || "";
  return {
    "access-control-allow-origin": origin === allowedOrigin ? origin : "null",
    "access-control-allow-methods": "POST, GET, DELETE, OPTIONS",
    "access-control-allow-headers": "authorization, content-type",
    "access-control-max-age": "86400",
    "vary": "origin",
  };
}

function numberEnv(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}
