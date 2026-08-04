import { beforeEach, describe, expect, it } from "vitest";
import { GET, POST } from "./route";
import { DELETE, GET as GET_ONE, PUT } from "./[id]/route";
import { POST as IMPORT } from "./import/route";

const entry = { cardName: "Atraxa, Praetors' Voice", quantity: 1, section: "commander" } as const;

describe("cloud deck API", () => {
  beforeEach(() => {
    globalThis.__magicMobileDevelopmentDecks = new Map();
    delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    delete process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  });

  it("creates, lists, updates, reads, and deletes a deck", async () => {
    const createdResponse = await POST(jsonRequest("http://localhost/api/decks", "POST", {
      name: "Atraxa",
      entries: [entry]
    }));
    expect(createdResponse.status).toBe(201);
    const { deck: created } = await createdResponse.json();
    expect(created.revision).toBe(1);

    const listResponse = await GET(new Request("http://localhost/api/decks"));
    const list = await listResponse.json();
    expect(list.decks).toHaveLength(1);

    const context = { params: Promise.resolve({ id: created.id as string }) };
    const updatedResponse = await PUT(jsonRequest(`http://localhost/api/decks/${created.id}`, "PUT", {
      name: "Atraxa updated",
      revision: 1
    }), context);
    const { deck: updated } = await updatedResponse.json();
    expect(updated).toMatchObject({ name: "Atraxa updated", revision: 2 });

    const conflictResponse = await PUT(jsonRequest(`http://localhost/api/decks/${created.id}`, "PUT", {
      name: "Stale",
      revision: 1
    }), context);
    expect(conflictResponse.status).toBe(409);

    expect((await GET_ONE(new Request(`http://localhost/api/decks/${created.id}`), context)).status).toBe(200);
    expect((await DELETE(new Request(`http://localhost/api/decks/${created.id}`, { method: "DELETE" }), context)).status).toBe(204);
    expect((await GET_ONE(new Request(`http://localhost/api/decks/${created.id}`), context)).status).toBe(404);
  });

  it("imports pasted deck text into the same persistent contract", async () => {
    const response = await IMPORT(jsonRequest("http://localhost/api/decks/import", "POST", {
      name: "Imported Atraxa",
      sourceText: "Commander\n1 Atraxa, Praetors' Voice\nDeck\n1 Sol Ring"
    }));
    expect(response.status).toBe(201);
    const { deck } = await response.json();
    expect(deck).toMatchObject({ name: "Imported Atraxa", revision: 1, source: { kind: "paste" } });
    expect(deck.entries).toHaveLength(2);
  });

  it("rejects invalid input with a stable error envelope", async () => {
    const response = await POST(jsonRequest("http://localhost/api/decks", "POST", { name: "Empty", entries: [] }));
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "Deck entries are required." });
  });
});

const jsonRequest = (url: string, method: string, body: unknown) => new Request(url, {
  method,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body)
});
