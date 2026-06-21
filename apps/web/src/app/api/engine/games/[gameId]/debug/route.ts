interface GameDebugRouteContext {
  params: Promise<{ gameId: string }>;
}

export async function GET(_request: Request, context: GameDebugRouteContext): Promise<Response> {
  const { gameId } = await context.params;
  const gatewayUrl = process.env.XMAGE_GATEWAY_URL?.replace(/\/$/, "");

  if (!gatewayUrl || process.env.ENGINE_MODE !== "xmage") {
    return Response.json(
      { error: "XMage protocol debug is available only when ENGINE_MODE=xmage and XMAGE_GATEWAY_URL are set." },
      { status: 503 }
    );
  }

  const response = await fetch(`${gatewayUrl}/games/${encodeURIComponent(gameId)}/debug`, {
    headers: {
      Accept: "application/json"
    }
  });

  const text = await response.text();
  return new Response(text, {
    status: response.status,
    headers: {
      "Content-Type": response.headers.get("Content-Type") ?? "application/json"
    }
  });
}
