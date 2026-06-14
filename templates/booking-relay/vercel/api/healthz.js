export default function handler(request, response) {
  response.status(200).json({
    ok: true,
    allowedOrigin: process.env.ALLOWED_ORIGIN || "",
    storage: "vercel-blob",
  });
}
