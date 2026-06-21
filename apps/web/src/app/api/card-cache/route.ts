import { readScryfallCacheMetadata, syncScryfallCache } from "@magicmobile/card-data";

let syncPromise: Promise<unknown> | undefined;

export async function GET(): Promise<Response> {
  return Response.json(await readScryfallCacheMetadata());
}

export async function POST(): Promise<Response> {
  if (!syncPromise) {
    syncPromise = syncScryfallCache().finally(() => {
      syncPromise = undefined;
    });
  }

  const metadata = await syncPromise;
  return Response.json(metadata);
}
