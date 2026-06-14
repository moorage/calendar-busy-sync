import { list } from "@vercel/blob";

export function requestKey(inboxId, requestId) {
  return `inbox/${inboxId}/requests/${requestId}.json`;
}

export async function countPending(inboxId) {
  const result = await list({
    prefix: `inbox/${inboxId}/requests/`,
    limit: Number(process.env.MAX_PENDING_REQUESTS || "100") + 1,
  });
  return result.blobs.length;
}
