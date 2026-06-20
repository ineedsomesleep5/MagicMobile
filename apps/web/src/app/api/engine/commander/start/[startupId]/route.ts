import { getCommanderStartup } from "@/lib/commander-startups";

interface CommanderStartupRouteContext {
  params: Promise<{ startupId: string }>;
}

export async function GET(_request: Request, context: CommanderStartupRouteContext): Promise<Response> {
  const { startupId } = await context.params;
  const startup = getCommanderStartup(startupId);
  if (!startup) {
    return Response.json(
      { startupId, status: "failed", error: "Commander startup was not found or expired." },
      { status: 404 }
    );
  }

  return Response.json(startup);
}
