import {
  chainHexId,
  routeChainIds,
  supportedChainById,
  walletChainParameter,
} from "@/config/networks";
import type { Eip1193Provider } from "@/types/wallet";

function providerErrorCode(error: unknown): number | null {
  if (typeof error !== "object" || error === null || !("code" in error)) {
    return null;
  }

  const errorCode = (error as { code?: unknown }).code;
  return typeof errorCode === "number" ? errorCode : null;
}

export async function addWalletChain(
  provider: Eip1193Provider,
  chainId: number,
): Promise<void> {
  supportedChainById(chainId);
  await provider.request({
    method: "wallet_addEthereumChain",
    params: [walletChainParameter(chainId)],
  });
}

export async function addWalletRouteChains(
  provider: Eip1193Provider,
  sourceChainId: number,
  destinationChainId: number,
): Promise<number[]> {
  const chainIds = routeChainIds(sourceChainId, destinationChainId);

  for (const chainId of chainIds) {
    await addWalletChain(provider, chainId);
  }

  return chainIds;
}

export async function switchWalletChain(
  provider: Eip1193Provider,
  chainId: number,
): Promise<void> {
  supportedChainById(chainId);

  const chainIdHex = chainHexId(chainId);
  const switchRequest = {
    method: "wallet_switchEthereumChain",
    params: [{ chainId: chainIdHex }],
  } as const;

  try {
    await provider.request(switchRequest);
  } catch (error) {
    if (providerErrorCode(error) !== 4902) {
      throw error;
    }

    await addWalletChain(provider, chainId);
    await provider.request(switchRequest);
  }
}
