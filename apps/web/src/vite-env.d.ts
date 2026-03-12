/// <reference types="vite/client" />

import type { Eip6963ProviderDetail } from "@/types/wallet";

declare global {
  interface WindowEventMap {
    "eip6963:announceProvider": CustomEvent<Eip6963ProviderDetail>;
  }
}
