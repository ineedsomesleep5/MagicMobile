export async function POST(request: Request) {
  if (process.env.NODE_ENV === "production" || process.env.ENABLE_XMAGE_FIXTURES !== "true") {
    return Response.json({ error: "xmage_fixtures_disabled" }, { status: 404 });
  }

  const gatewayUrl = process.env.XMAGE_GATEWAY_URL?.replace(/\/$/, "");
  if (!gatewayUrl) {
    return Response.json({ error: "xmage_gateway_unconfigured" }, { status: 503 });
  }

  const response = await fetch(`${gatewayUrl}/dev/xmage-fixtures/commander`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: await request.text()
  });

  return new Response(await response.text(), {
    status: response.status,
    headers: { "Content-Type": response.headers.get("Content-Type") ?? "application/json" }
  });
}
