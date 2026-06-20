import type { HybridAction, HybridActionType } from "@magicmobile/shared";
import type { HybridActionValidation } from "./types";

export const hybridActionTypes = [
  "play_land",
  "cast_spell",
  "move_card",
  "tap_permanent",
  "untap_permanent",
  "attack_player",
  "add_counter",
  "create_token",
  "change_life",
  "update_commander_damage",
  "pass_priority"
] as const satisfies readonly HybridActionType[];

const hybridActionTypeSet = new Set<string>(hybridActionTypes);

export function validateHybridAction(action: Partial<HybridAction> & { type?: string }): HybridActionValidation {
  const errors: string[] = [];

  if (!action.playerId) {
    errors.push("playerId is required");
  }

  if (!action.type || !hybridActionTypeSet.has(action.type)) {
    errors.push("type must be a supported hybrid action");
  }

  return {
    errors,
    valid: errors.length === 0
  };
}
