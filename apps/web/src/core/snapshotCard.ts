import { arr, bool, get, type J } from "./json";

/**
 * The pinned CardView stores ordered symbol arrays, not a `manaCost` string. Keep the two printed
 * halves separate; never consult rules, mana value or payment text (OnDeviceSnapshotAdapter.printedManaCost).
 */
export const printedManaCost = (value: J): string | undefined => {
  if (bool(get(value, "hideInfo")) === true || bool(get(value, "faceDown")) === true) return undefined;
  const halves: string[] = [];
  for (const key of ["manaCostLeftStr", "manaCostRightStr"]) {
    const raw = get(value, key);
    if (raw === undefined) continue;
    const symbols = arr(raw);
    if (!symbols || !symbols.every((s) => typeof s === "string")) return undefined;
    const cost = (symbols as string[]).join("");
    if (cost.length > 0) halves.push(cost);
  }
  return halves.length === 0 ? undefined : halves.join(" // ");
};
