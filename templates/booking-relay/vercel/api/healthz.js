export default function handler(request, response) {
  const hasBlobToken = Boolean(process.env.BLOB_READ_WRITE_TOKEN);
  response.status(hasBlobToken ? 200 : 503).json({
    ok: hasBlobToken,
    allowedOrigin: process.env.ALLOWED_ORIGIN || "",
    storage: "vercel-blob",
    storageReady: hasBlobToken,
  });
}
