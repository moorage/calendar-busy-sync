import { del } from "@vercel/blob";
import { assertAdmin, cors, json } from "../../../../../lib/http.js";
import { requestKey } from "../../../../../lib/inbox-store.js";

export default async function handler(request, response) {
  cors(request, response);
  if (request.method === "OPTIONS") {
    response.status(204).end();
    return;
  }

  if (request.method !== "DELETE") {
    json(response, 404, { error: "not_found" });
    return;
  }

  const authError = assertAdmin(request, response);
  if (authError) return;

  await del(requestKey(request.query.inboxId, request.query.requestId));
  json(response, 200, { ok: true });
}
