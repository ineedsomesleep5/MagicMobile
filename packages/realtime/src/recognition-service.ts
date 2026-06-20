import type { RecognitionService, ZoneName } from "@magicmobile/shared";

export class MockRecognitionService implements RecognitionService {
  async clickToIdentifyCard(_input: { imageId: string; x: number; y: number }): Promise<string[]> {
    return [];
  }

  async suggestCardMatch(input: { text: string }): Promise<string[]> {
    const query = input.text.trim();
    return query ? [query] : [];
  }

  async confirmCardMatch(_input: { cardName: string }): Promise<{ confirmed: true }> {
    return { confirmed: true };
  }

  async suggestZoneChange(_input: { cardName: string }): Promise<ZoneName[]> {
    return ["battlefield", "graveyard", "exile"];
  }
}
