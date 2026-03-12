import { LocalMockAdapter } from "@/adapters/localMockAdapter";
import { UniswapV3Adapter } from "@/adapters/uniswapV3Adapter";
import type { SwapAdapter } from "@/types/swap";

export function createSwapAdapter(): SwapAdapter {
  const mode = (import.meta.env.VITE_SWAP_MODE ?? "local").toLowerCase();
  if (mode === "uniswap") {
    return new UniswapV3Adapter();
  }
  return new LocalMockAdapter();
}
