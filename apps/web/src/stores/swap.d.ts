import type { QuoteResult, SwapStatus, TokenInfo } from "@/types/swap";
import type { WalletOption } from "@/types/wallet";
export declare const useSwapStore: import("pinia").StoreDefinition<"swap", {
    availableWallets: WalletOption[];
    selectedWalletUuid: string | null;
    walletAddress: `0x${string}` | null;
    walletConnected: boolean;
    walletChainId: number | null;
    selectedChainId: number;
    destinationChainId: number;
    fromToken: TokenInfo;
    amountInText: string;
    status: SwapStatus;
    statusMessage: string;
    walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
    walletNetworkActionChainId: number | null;
    quote: QuoteResult | null;
    allowance: bigint;
    fromBalance: bigint;
    toBalance: bigint;
    lastTxHash: `0x${string}` | null;
}, {
    activeWallet(state: {
        availableWallets: {
            info: {
                uuid: string;
                name: string;
                icon: string;
                rdns: string;
            };
            provider: {
                request: (arguments_: import("@/types/wallet").Eip1193RequestArguments) => Promise<unknown>;
                on?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
                removeListener?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
            };
        }[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: {
            chainId: number;
            address: `0x${string}`;
            symbol: string;
            name: string;
            decimals: number;
            isNative: boolean;
        };
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: {
            amountOut: bigint;
            priceImpactBps: number;
            routeLabel: string;
        } | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    } & import("pinia").PiniaCustomStateProperties<{
        availableWallets: WalletOption[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: TokenInfo;
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: QuoteResult | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    }>): WalletOption | null;
    destinationToken(state: {
        availableWallets: {
            info: {
                uuid: string;
                name: string;
                icon: string;
                rdns: string;
            };
            provider: {
                request: (arguments_: import("@/types/wallet").Eip1193RequestArguments) => Promise<unknown>;
                on?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
                removeListener?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
            };
        }[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: {
            chainId: number;
            address: `0x${string}`;
            symbol: string;
            name: string;
            decimals: number;
            isNative: boolean;
        };
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: {
            amountOut: bigint;
            priceImpactBps: number;
            routeLabel: string;
        } | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    } & import("pinia").PiniaCustomStateProperties<{
        availableWallets: WalletOption[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: TokenInfo;
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: QuoteResult | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    }>): TokenInfo | null;
    parsedAmountIn(state: {
        availableWallets: {
            info: {
                uuid: string;
                name: string;
                icon: string;
                rdns: string;
            };
            provider: {
                request: (arguments_: import("@/types/wallet").Eip1193RequestArguments) => Promise<unknown>;
                on?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
                removeListener?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
            };
        }[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: {
            chainId: number;
            address: `0x${string}`;
            symbol: string;
            name: string;
            decimals: number;
            isNative: boolean;
        };
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: {
            amountOut: bigint;
            priceImpactBps: number;
            routeLabel: string;
        } | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    } & import("pinia").PiniaCustomStateProperties<{
        availableWallets: WalletOption[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: TokenInfo;
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: QuoteResult | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    }>): bigint;
    formattedFromBalance(state: {
        availableWallets: {
            info: {
                uuid: string;
                name: string;
                icon: string;
                rdns: string;
            };
            provider: {
                request: (arguments_: import("@/types/wallet").Eip1193RequestArguments) => Promise<unknown>;
                on?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
                removeListener?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
            };
        }[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: {
            chainId: number;
            address: `0x${string}`;
            symbol: string;
            name: string;
            decimals: number;
            isNative: boolean;
        };
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: {
            amountOut: bigint;
            priceImpactBps: number;
            routeLabel: string;
        } | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    } & import("pinia").PiniaCustomStateProperties<{
        availableWallets: WalletOption[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: TokenInfo;
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: QuoteResult | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    }>): string;
    formattedToBalance(state: {
        availableWallets: {
            info: {
                uuid: string;
                name: string;
                icon: string;
                rdns: string;
            };
            provider: {
                request: (arguments_: import("@/types/wallet").Eip1193RequestArguments) => Promise<unknown>;
                on?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
                removeListener?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
            };
        }[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: {
            chainId: number;
            address: `0x${string}`;
            symbol: string;
            name: string;
            decimals: number;
            isNative: boolean;
        };
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: {
            amountOut: bigint;
            priceImpactBps: number;
            routeLabel: string;
        } | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    } & import("pinia").PiniaCustomStateProperties<{
        availableWallets: WalletOption[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: TokenInfo;
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: QuoteResult | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    }>): string;
    formattedQuote(state: {
        availableWallets: {
            info: {
                uuid: string;
                name: string;
                icon: string;
                rdns: string;
            };
            provider: {
                request: (arguments_: import("@/types/wallet").Eip1193RequestArguments) => Promise<unknown>;
                on?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
                removeListener?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
            };
        }[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: {
            chainId: number;
            address: `0x${string}`;
            symbol: string;
            name: string;
            decimals: number;
            isNative: boolean;
        };
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: {
            amountOut: bigint;
            priceImpactBps: number;
            routeLabel: string;
        } | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    } & import("pinia").PiniaCustomStateProperties<{
        availableWallets: WalletOption[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: TokenInfo;
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: QuoteResult | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    }>): string;
    connectedWalletName(state: {
        availableWallets: {
            info: {
                uuid: string;
                name: string;
                icon: string;
                rdns: string;
            };
            provider: {
                request: (arguments_: import("@/types/wallet").Eip1193RequestArguments) => Promise<unknown>;
                on?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
                removeListener?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
            };
        }[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: {
            chainId: number;
            address: `0x${string}`;
            symbol: string;
            name: string;
            decimals: number;
            isNative: boolean;
        };
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: {
            amountOut: bigint;
            priceImpactBps: number;
            routeLabel: string;
        } | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    } & import("pinia").PiniaCustomStateProperties<{
        availableWallets: WalletOption[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: TokenInfo;
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: QuoteResult | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    }>): string | null;
    walletRouteChainIds(state: {
        availableWallets: {
            info: {
                uuid: string;
                name: string;
                icon: string;
                rdns: string;
            };
            provider: {
                request: (arguments_: import("@/types/wallet").Eip1193RequestArguments) => Promise<unknown>;
                on?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
                removeListener?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
            };
        }[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: {
            chainId: number;
            address: `0x${string}`;
            symbol: string;
            name: string;
            decimals: number;
            isNative: boolean;
        };
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: {
            amountOut: bigint;
            priceImpactBps: number;
            routeLabel: string;
        } | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    } & import("pinia").PiniaCustomStateProperties<{
        availableWallets: WalletOption[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: TokenInfo;
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: QuoteResult | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    }>): number[];
    walletChainSupported(state: {
        availableWallets: {
            info: {
                uuid: string;
                name: string;
                icon: string;
                rdns: string;
            };
            provider: {
                request: (arguments_: import("@/types/wallet").Eip1193RequestArguments) => Promise<unknown>;
                on?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
                removeListener?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
            };
        }[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: {
            chainId: number;
            address: `0x${string}`;
            symbol: string;
            name: string;
            decimals: number;
            isNative: boolean;
        };
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: {
            amountOut: bigint;
            priceImpactBps: number;
            routeLabel: string;
        } | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    } & import("pinia").PiniaCustomStateProperties<{
        availableWallets: WalletOption[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: TokenInfo;
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: QuoteResult | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    }>): boolean;
    walletNetworkActionPending(state: {
        availableWallets: {
            info: {
                uuid: string;
                name: string;
                icon: string;
                rdns: string;
            };
            provider: {
                request: (arguments_: import("@/types/wallet").Eip1193RequestArguments) => Promise<unknown>;
                on?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
                removeListener?: ((eventName: string, listener: (...arguments_: unknown[]) => void) => void) | undefined;
            };
        }[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: {
            chainId: number;
            address: `0x${string}`;
            symbol: string;
            name: string;
            decimals: number;
            isNative: boolean;
        };
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: {
            amountOut: bigint;
            priceImpactBps: number;
            routeLabel: string;
        } | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    } & import("pinia").PiniaCustomStateProperties<{
        availableWallets: WalletOption[];
        selectedWalletUuid: string | null;
        walletAddress: `0x${string}` | null;
        walletConnected: boolean;
        walletChainId: number | null;
        selectedChainId: number;
        destinationChainId: number;
        fromToken: TokenInfo;
        amountInText: string;
        status: SwapStatus;
        statusMessage: string;
        walletNetworkAction: "adding-chain" | "adding-route-chains" | "switching-route-chain" | null;
        walletNetworkActionChainId: number | null;
        quote: QuoteResult | null;
        allowance: bigint;
        fromBalance: bigint;
        toBalance: bigint;
        lastTxHash: `0x${string}` | null;
    }>): boolean;
}, {
    initialize(): Promise<void>;
    startDiscovery(): void;
    connectWallet(walletUuid?: string | null): Promise<void>;
    disconnectWallet(): void;
    setWallet(walletUuid: string): void;
    handleAccountsChanged(accounts: string[]): Promise<void>;
    handleChainChanged(chainIdHex: string): Promise<void>;
    syncRouteWithWalletChain(): void;
    updateRouteSourceChain(chainId: number): void;
    setChain(chainId: number): void;
    selectRouteSourceChain(chainId: number): Promise<void>;
    setDestinationChain(chainId: number): void;
    setSourceToken(tokenAddress: `0x${string}`): void;
    setAmount(text: string): void;
    swapDirection(): void;
    addChainToWallet(chainId: number): Promise<void>;
    addRouteChainsToWallet(): Promise<void>;
    switchWalletToChain(chainId: number): Promise<void>;
    ensureSelectedChain(): Promise<void>;
    readBalanceForToken(token: TokenInfo): Promise<bigint>;
    refreshBalances(): Promise<void>;
    refreshQuote(): Promise<void>;
    approve(): Promise<void>;
    executeSwap(): Promise<void>;
}>;
