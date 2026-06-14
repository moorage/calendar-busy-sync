const MAX_BODY_BYTES = 16 * 1024;

export function cors(request, response) {
  const origin = request.headers.origin || "";
  const allowedOrigin = process.env.ALLOWED_ORIGIN || "";
  response.setHeader("access-control-allow-origin", origin === allowedOrigin ? origin : "null");
  response.setHeader("access-control-allow-methods", "POST, GET, DELETE, OPTIONS");
  response.setHeader("access-control-allow-headers", "authorization, content-type");
  response.setHeader("access-control-max-age", "86400");
  response.setHeader("vary", "origin");
}

export function json(response, status, body) {
  response.status(status).json(body);
}

export function assertAllowedOrigin(request, response) {
  const allowedOrigin = process.env.ALLOWED_ORIGIN || "";
  const origin = request.headers.origin || "";
  if (!allowedOrigin || origin !== allowedOrigin) {
    json(response, 403, { error: "origin_not_allowed" });
    return true;
  }
  return false;
}

export function assertAdmin(request, response) {
  const token = process.env.INBOX_ADMIN_TOKEN || "";
  if (!token || request.headers.authorization !== `Bearer ${token}`) {
    json(response, 401, { error: "unauthorized" });
    return true;
  }
  return false;
}

export async function readJSON(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) {
      throw new Error("payload_too_large");
    }
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

export function validateEnvelope(envelope, inboxId) {
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
