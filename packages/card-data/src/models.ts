import type { CardIdentity, ColorSymbol } from "@magicmobile/shared";

export type CommanderLegality = "legal" | "not_legal" | "banned" | "unknown";

export interface MagicMobileCard extends CardIdentity {
  scryfallId?: string;
  manaCost?: string;
  colors?: ColorSymbol[];
  legalities?: {
    commander?: CommanderLegality;
  };
  artist?: string;
  copyright?: string;
}

export interface ScryfallCardLike {
  id: string;
  name: string;
  cmc: number;
  color_identity: string[];
  type_line: string;
  oracle_text?: string;
  mana_cost?: string;
  colors?: string[];
  legalities?: {
    commander?: CommanderLegality;
  };
  artist?: string;
  copyright?: string;
}
