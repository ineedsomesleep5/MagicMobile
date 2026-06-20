import { InMemoryRealtimeGateway, InMemoryRoomService, MockRecognitionService } from "@magicmobile/realtime";
import { MockVideoProvider } from "@magicmobile/video";

interface MagicMobileRoomRuntime {
  realtimeGateway: InMemoryRealtimeGateway;
  recognitionService: MockRecognitionService;
  roomService: InMemoryRoomService;
  videoProvider: MockVideoProvider;
}

const globalRuntime = globalThis as typeof globalThis & {
  __magicMobileRoomRuntime?: MagicMobileRoomRuntime;
};

globalRuntime.__magicMobileRoomRuntime ??= createRoomRuntime();

export const { realtimeGateway, recognitionService, roomService, videoProvider } = globalRuntime.__magicMobileRoomRuntime;

function createRoomRuntime(): MagicMobileRoomRuntime {
  const gateway = new InMemoryRealtimeGateway();

  return {
    realtimeGateway: gateway,
    recognitionService: new MockRecognitionService(),
    roomService: new InMemoryRoomService({ gateway }),
    videoProvider: new MockVideoProvider()
  };
}
