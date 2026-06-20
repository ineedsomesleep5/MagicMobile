const icon = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="12" fill="#111916"/>
  <path d="M32 7 51 20v24L32 57 13 44V20L32 7Z" fill="#f2d48a"/>
  <path d="M32 14 45 23v17L32 50 19 40V23l13-9Z" fill="#1c6650"/>
  <path d="M32 19c7 7 10 13 10 19 0 5-4 9-10 9s-10-4-10-9c0-6 3-12 10-19Z" fill="#48c78e"/>
</svg>`;

export function GET(): Response {
  return new Response(icon, {
    headers: {
      "Content-Type": "image/svg+xml",
      "Cache-Control": "public, max-age=86400"
    }
  });
}
