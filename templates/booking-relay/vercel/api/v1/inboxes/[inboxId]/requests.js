import { list, put } from "@vercel/blob";
import { assertAllowedOrigin, assertAdmin, cors, json, readJSON, validateEnvelope } from "../../../../lib/http.js";
import { countPending, requestKey } from "../../../../lib/inbox-store.js";

const MAX_BODY_BYTES = 16 * 1024;
const DEFAULT_MAX_PENDING = 100;

export default async function handler(request, response) {
  cors(request, response);
  if (request.method === "OPTIONS") {
    response.status(204).end();
    return;
  }

  const { inboxId } = request.query;
  if (request.method === "POST") {
    const originError = assertAllowedOrigin(request, response);
    if (originError) return;

    if (Number(request.headers["content-length"] || "0") > MAX_BODY_BYTES) {
      json(response, 413, { error: "payload_too_large" });
      return;
    }

    const envelope = await readJSON(request);
    const validation = validateEnvelope(envelope, inboxId);
    if (!validation.ok) {
      json(response, 400, { error: validation.error });
      return;
    }

    const pendingCount = await countPending(inboxId);
    if (pendingCount >= Number(process.env.MAX_PENDING_REQUESTS || DEFAULT_MAX_PENDING)) {
      json(response, 429, { error: "inbox_full" });
      return;
    }

    await put(requestKey(inboxId, envelope.requestID), JSON.stringify(envelope), {
      access: "public",
      contentType: "application/json",
      addRandomSuffix: false,
    });
    json(response, 202, { ok: true });
    return;
  }

  if (request.method === "GET") {
    const authError = assertAdmin(request, response);
    if (authError) return;

    const result = await list({
      prefix: `inbox/${inboxId}/requests/`,
      cursor: request.query.cursor,
      limit: 50,
    });
    const requests = [];
    for (const blob of result.blobs) {
      const blobResponse = await fetch(blob.url);
      requests.push(await blobResponse.json());
    }
    json(response, 200, { requests, cursor: result.cursor || null });
    return;
  }

  json(response, 404, { error: "not_found" });
}
