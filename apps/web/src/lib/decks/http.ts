import type { DeckImportRequest } from "@magicmobile/shared";
import { DeckImportError } from "@magicmobile/deck";
import { NextResponse } from "next/server";
import { DeckAuthError } from "../supabase/request";
import { DeckRepositoryError } from "./repository";
import { DeckRequestError } from "./validation";

const MAX_FILE_BYTES = 2 * 1024 * 1024;
const ALLOWED_FILE_EXTENSIONS = /\.(?:txt|dec|csv)$/i;

export const readJsonBody = async (request: Request): Promise<unknown> => {
  try {
    return await request.json();
  } catch {
    throw new DeckRequestError("Request body must be valid JSON.");
  }
};

export const readDeckImportBody = async (request: Request): Promise<DeckImportRequest> => {
  if (request.headers.get("content-type")?.toLowerCase().includes("multipart/form-data")) {
    const data = await request.formData();
    const file = data.get("file");
    if (!(file instanceof File)) throw new DeckRequestError("Choose a .txt, .dec, or .csv deck file.");
    if (!ALLOWED_FILE_EXTENSIONS.test(file.name)) throw new DeckRequestError("Deck files must use .txt, .dec, or .csv.");
    if (file.size > MAX_FILE_BYTES) throw new DeckRequestError("Deck file is larger than 2 MB.", 413);
    const name = stringField(data.get("name"));
    return { sourceText: await file.text(), filename: file.name, ...(name ? { name } : {}) };
  }

  const value = await readJsonBody(request);
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new DeckRequestError("Request body must be a JSON object.");
  const record = value as Record<string, unknown>;
  const sourceText = stringProperty(record.sourceText);
  const sourceURL = stringProperty(record.sourceURL);
  const filename = stringProperty(record.filename);
  const name = stringProperty(record.name);
  return {
    ...(sourceText ? { sourceText } : {}),
    ...(sourceURL ? { sourceURL } : {}),
    ...(filename ? { filename } : {}),
    ...(name ? { name } : {})
  };
};

export const deckErrorResponse = (error: unknown): NextResponse<{ error: string }> => {
  if (
    error instanceof DeckAuthError
    || error instanceof DeckRequestError
    || error instanceof DeckRepositoryError
    || error instanceof DeckImportError
  ) {
    return NextResponse.json({ error: error.message }, { status: error.status });
  }
  console.error("Unexpected cloud deck API error", error);
  return NextResponse.json({ error: "Cloud deck operation failed." }, { status: 500 });
};

const stringProperty = (value: unknown): string | undefined =>
  typeof value === "string" && value.trim() ? value.trim() : undefined;
const stringField = (value: FormDataEntryValue | null): string | undefined =>
  typeof value === "string" && value.trim() ? value.trim() : undefined;
