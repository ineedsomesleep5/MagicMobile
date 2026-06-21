import { createRuntimeEngineAdapter } from "@/lib/engine";

export async function GET() {
  if (process.env.ENGINE_MODE !== "xmage" || !process.env.XMAGE_GATEWAY_URL) {
    return Response.json({
      status: "unavailable",
      reason: "Real Commander play requires ENGINE_MODE=xmage and XMAGE_GATEWAY_URL to point at the XMage gateway.",
      checkedAt: new Date().toISOString(),
      recoveryAction: "restart_gateway"
    });
  }

  const engine = createRuntimeEngineAdapter({ mode: "xmage" });
  return Response.json(await engine.getHealth());
}
