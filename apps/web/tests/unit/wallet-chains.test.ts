import { describe, expect, it, vi } from "vitest";
import {
  addWalletChain,
  addWalletRouteChains,
  switchWalletChain,
} from "@/services/walletChains";
import type { Eip1193Provider } from "@/types/wallet";

function providerWithRequest(request: Eip1193Provider["request"]): Eip1193Provider {
  return { request };
}

describe("wallet chain services", () => {
  it("adds a supported chain to the wallet", async () => {
    const request = vi.fn().mockResolvedValue(undefined);
    const provider = providerWithRequest(request);

    await addWalletChain(provider, 31338);

    expect(request).toHaveBeenCalledWith({
      method: "wallet_addEthereumChain",
      params: [
        expect.objectContaining({
          chainId: "0x7a6a",
          chainName: "Ethereum",
          rpcUrls: ["http://127.0.0.1:8545"],
        }),
      ],
    });
  });

  it("adds both route chains to the wallet", async () => {
    const request = vi.fn().mockResolvedValue(undefined);
    const provider = providerWithRequest(request);

    await addWalletRouteChains(provider, 31338, 31339);

    expect(request).toHaveBeenNthCalledWith(1, {
      method: "wallet_addEthereumChain",
      params: [
        expect.objectContaining({
          chainId: "0x7a6a",
          chainName: "Ethereum",
          rpcUrls: ["http://127.0.0.1:8545"],
        }),
      ],
    });
    expect(request).toHaveBeenNthCalledWith(2, {
      method: "wallet_addEthereumChain",
      params: [
        expect.objectContaining({
          chainId: "0x7a6b",
          chainName: "Base",
          rpcUrls: ["http://127.0.0.1:8546"],
        }),
      ],
    });
  });

  it("adds an unknown chain and retries the switch", async () => {
    const request = vi
      .fn()
      .mockRejectedValueOnce({ code: 4902 })
      .mockResolvedValueOnce(undefined)
      .mockResolvedValueOnce(undefined);
    const provider = providerWithRequest(request);

    await switchWalletChain(provider, 31339);

    expect(request).toHaveBeenNthCalledWith(1, {
      method: "wallet_switchEthereumChain",
      params: [{ chainId: "0x7a6b" }],
    });
    expect(request).toHaveBeenNthCalledWith(2, {
      method: "wallet_addEthereumChain",
      params: [
        expect.objectContaining({
          chainId: "0x7a6b",
          chainName: "Base",
        }),
      ],
    });
    expect(request).toHaveBeenNthCalledWith(3, {
      method: "wallet_switchEthereumChain",
      params: [{ chainId: "0x7a6b" }],
    });
  });
});
