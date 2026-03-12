import { beforeEach, describe, expect, it, vi } from "vitest";
import { createPinia, setActivePinia } from "pinia";
import { SUPPORTED_TOKENS } from "@/config/tokens";
import { useSwapStore } from "@/stores/swap";
import type { WalletOption } from "@/types/wallet";
import {
  readTokenAllowance,
  readTokenBalance,
  requestWalletAccounts,
  requestWalletChainId,
} from "@/services/bridge";
import {
  addWalletChain,
  addWalletRouteChains,
  switchWalletChain,
} from "@/services/walletChains";

vi.mock("@/services/bridge", async () => {
  const actual = await vi.importActual<typeof import("@/services/bridge")>(
    "@/services/bridge",
  );

  return {
    ...actual,
    requestWalletAccounts: vi.fn(),
    requestWalletChainId: vi.fn(),
    readTokenBalance: vi.fn(),
    readTokenAllowance: vi.fn(),
    approveBridgeToken: vi.fn(),
    depositToBridge: vi.fn(),
  };
});

vi.mock("@/services/walletChains", () => ({
  addWalletChain: vi.fn(),
  addWalletRouteChains: vi.fn(),
  switchWalletChain: vi.fn(),
}));

vi.mock("@/services/walletDiscovery", () => ({
  startWalletDiscovery: vi.fn(() => () => undefined),
  subscribeWalletProvider: vi.fn(() => () => undefined),
}));

const mockedAddWalletChain = vi.mocked(addWalletChain);
const mockedRequestWalletAccounts = vi.mocked(requestWalletAccounts);
const mockedRequestWalletChainId = vi.mocked(requestWalletChainId);
const mockedReadTokenBalance = vi.mocked(readTokenBalance);
const mockedReadTokenAllowance = vi.mocked(readTokenAllowance);
const mockedAddWalletRouteChains = vi.mocked(addWalletRouteChains);
const mockedSwitchWalletChain = vi.mocked(switchWalletChain);

function walletOption(): WalletOption {
  return {
    info: {
      uuid: "wallet-1",
      name: "Test Wallet",
      icon: "",
      rdns: "test.wallet",
    },
    provider: {
      request: vi.fn(),
      on: vi.fn(),
      removeListener: vi.fn(),
    },
  };
}

describe("swap store", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    mockedAddWalletChain.mockReset();
    mockedRequestWalletAccounts.mockReset();
    mockedRequestWalletChainId.mockReset();
    mockedReadTokenBalance.mockReset();
    mockedReadTokenAllowance.mockReset();
    mockedAddWalletRouteChains.mockReset();
    mockedSwitchWalletChain.mockReset();
    mockedAddWalletChain.mockResolvedValue(undefined);
    mockedReadTokenBalance.mockResolvedValue(10n ** 18n);
    mockedReadTokenAllowance.mockResolvedValue(0n);
    mockedAddWalletRouteChains.mockResolvedValue([31338, 31339]);
    mockedSwitchWalletChain.mockResolvedValue();
  });

  it("stays idle when no wallet is connected", async () => {
    const store = useSwapStore();

    await store.initialize();

    expect(store.walletConnected).toBe(false);
    expect(store.status).toBe("idle");
    expect(store.statusMessage).toContain("Connect a wallet");
  });

  it("connects a discovered wallet and requires approval for ERC20 deposits", async () => {
    const store = useSwapStore();
    const wallet = walletOption();
    const erc20Token = SUPPORTED_TOKENS.find(
      (token) => token.chainId === store.selectedChainId && !token.isNative,
    );

    if (!erc20Token) {
      throw new Error("expected an ERC20 token in the supported token list");
    }

    store.availableWallets = [wallet];
    store.selectedWalletUuid = wallet.info.uuid;
    store.fromToken = erc20Token;

    mockedRequestWalletAccounts.mockResolvedValue([
      "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    ]);
    mockedRequestWalletChainId.mockResolvedValue(store.selectedChainId);

    await store.connectWallet(wallet.info.uuid);

    expect(store.walletConnected).toBe(true);
    expect(store.walletAddress).toBe("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    expect(store.status).toBe("approval-required");
  });

  it("aligns the bridge source chain to a supported wallet network on connect", async () => {
    const store = useSwapStore();
    const wallet = walletOption();

    store.availableWallets = [wallet];
    store.selectedWalletUuid = wallet.info.uuid;

    mockedRequestWalletAccounts.mockResolvedValue([
      "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    ]);
    mockedRequestWalletChainId.mockResolvedValue(store.destinationChainId);

    await store.connectWallet(wallet.info.uuid);

    expect(store.selectedChainId).toBe(store.walletChainId);
    expect(store.destinationChainId).not.toBe(store.selectedChainId);
  });

  it("adds a single supported chain to the connected wallet", async () => {
    const store = useSwapStore();
    const wallet = walletOption();

    store.availableWallets = [wallet];
    store.selectedWalletUuid = wallet.info.uuid;

    mockedRequestWalletAccounts.mockResolvedValue([
      "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    ]);
    mockedRequestWalletChainId.mockResolvedValue(store.selectedChainId);

    await store.connectWallet(wallet.info.uuid);
    await store.addChainToWallet(store.destinationChainId);

    expect(mockedAddWalletChain).toHaveBeenCalledWith(
      wallet.provider,
      store.destinationChainId,
    );
    expect(store.walletNetworkAction).toBeNull();
    expect(store.walletNetworkActionChainId).toBeNull();
  });

  it("adds the selected route chains to the connected wallet", async () => {
    const store = useSwapStore();
    const wallet = walletOption();

    store.availableWallets = [wallet];
    store.selectedWalletUuid = wallet.info.uuid;

    mockedRequestWalletAccounts.mockResolvedValue([
      "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    ]);
    mockedRequestWalletChainId.mockResolvedValue(store.selectedChainId);

    await store.connectWallet(wallet.info.uuid);
    await store.addRouteChainsToWallet();

    expect(mockedAddWalletRouteChains).toHaveBeenCalledWith(
      wallet.provider,
      store.selectedChainId,
      store.destinationChainId,
    );
    expect(store.walletNetworkAction).toBeNull();
  });

  it("switches the connected wallet to a route chain", async () => {
    const store = useSwapStore();
    const wallet = walletOption();

    store.availableWallets = [wallet];
    store.selectedWalletUuid = wallet.info.uuid;

    mockedRequestWalletAccounts.mockResolvedValue([
      "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    ]);
    mockedRequestWalletChainId
      .mockResolvedValueOnce(store.selectedChainId)
      .mockResolvedValueOnce(store.destinationChainId);

    await store.connectWallet(wallet.info.uuid);
    await store.switchWalletToChain(store.destinationChainId);

    expect(mockedSwitchWalletChain).toHaveBeenCalledWith(
      wallet.provider,
      store.destinationChainId,
    );
    expect(store.walletChainId).toBe(store.destinationChainId);
  });

  it("selects a new source chain and switches the wallet to match it", async () => {
    const store = useSwapStore();
    const wallet = walletOption();
    const initialSourceChainId = store.selectedChainId;
    const nextSourceChainId = store.destinationChainId;

    store.availableWallets = [wallet];
    store.selectedWalletUuid = wallet.info.uuid;

    mockedRequestWalletAccounts.mockResolvedValue([
      "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    ]);
    mockedRequestWalletChainId
      .mockResolvedValueOnce(initialSourceChainId)
      .mockResolvedValueOnce(nextSourceChainId);

    await store.connectWallet(wallet.info.uuid);
    await store.selectRouteSourceChain(nextSourceChainId);

    expect(store.selectedChainId).toBe(nextSourceChainId);
    expect(store.destinationChainId).toBe(initialSourceChainId);
    expect(mockedSwitchWalletChain).toHaveBeenCalledWith(wallet.provider, nextSourceChainId);
    expect(store.walletChainId).toBe(nextSourceChainId);
  });
});
