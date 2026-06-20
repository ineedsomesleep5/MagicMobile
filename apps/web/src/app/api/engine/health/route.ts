import { createRuntimeEngineAdapter } from "@/lib/engine";

export async function GET() {
  const engine = createRuntimeEngineAdapter();
  return Response.json(await engine.getHealth());
}
