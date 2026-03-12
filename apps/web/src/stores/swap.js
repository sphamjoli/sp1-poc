import { defineStore } from "pinia";
import { approveBridgeToken, bridgePreview, chainBridgeAddress, depositToBridge, destinationTokenForSource, readTokenAllowance, readTokenBalance, requestWalletAccounts, requestWalletChainId, sourceChainTokens, } from "@/services/bridge";
import { addWalletChain, addWalletRouteChains, switchWalletChain, } from "@/services/walletChains";
import { startWalletDiscovery, subscribeWalletProvider, } from "@/services/walletDiscovery";
import { chainLabel, routeChainIds } from "@/config/networks";
import { DEFAULT_CHAIN_ID, SUPPORTED_CHAINS } from "@/config/tokens";
import { formatUnits, parseUnits } from "@/utils/amount";
const LAST_CONNECTED_WALLET_KEY = "bridge:last-wallet";
let stopWalletDiscovery = null;
let stopWalletProviderSubscription = null;
function chainTokens(chainId) {
    return sourceChainTokens(chainId);
}
function defaultDestinationChainId(sourceChainId) {
    return SUPPORTED_CHAINS.find((chain) => chain.id !== sourceChainId)?.id ?? sourceChainId;
}
function defaultSourceToken(chainId) {
    const tokens = chainTokens(chainId);
    if (tokens.length === 0) {
        throw new Error(`No tokens configured for chain ${chainId}`);
    }
    return tokens[0];
}
function isSupportedWalletChain(chainId) {
    return chainId !== null && SUPPORTED_CHAINS.some((chain) => chain.id === chainId);
}
function readStoredWalletId() {
    if (typeof window === "undefined") {
        return null;
    }
    return window.localStorage.getItem(LAST_CONNECTED_WALLET_KEY);
}
function storeWalletId(walletId) {
    if (typeof window === "undefined") {
        return;
    }
    if (walletId) {
        window.localStorage.setItem(LAST_CONNECTED_WALLET_KEY, walletId);
        return;
    }
    window.localStorage.removeItem(LAST_CONNECTED_WALLET_KEY);
}
export const useSwapStore = defineStore("swap", {
    state: () => {
        const selectedChainId = DEFAULT_CHAIN_ID;
        const destinationChainId = defaultDestinationChainId(selectedChainId);
        const fromToken = defaultSourceToken(selectedChainId);
        return {
            availableWallets: [],
            selectedWalletUuid: readStoredWalletId(),
            walletAddress: null,
            walletConnected: false,
            walletChainId: null,
            selectedChainId,
            destinationChainId,
            fromToken,
            amountInText: "1.0",
            status: "idle",
            statusMessage: "Connect a wallet to prepare a bridge transfer",
            walletNetworkAction: null,
            walletNetworkActionChainId: null,
            quote: null,
            allowance: 0n,
            fromBalance: 0n,
            toBalance: 0n,
            lastTxHash: null,
        };
    },
    getters: {
        activeWallet(state) {
            if (!state.selectedWalletUuid) {
                return state.availableWallets[0] ?? null;
            }
            return (state.availableWallets.find((wallet) => wallet.info.uuid === state.selectedWalletUuid) ?? null);
        },
        destinationToken(state) {
            return destinationTokenForSource(state.fromToken, state.destinationChainId);
        },
        parsedAmountIn(state) {
            try {
                return parseUnits(state.amountInText, state.fromToken.decimals);
            }
            catch {
                return 0n;
            }
        },
        formattedFromBalance(state) {
            return formatUnits(state.fromBalance, state.fromToken.decimals, 4);
        },
        formattedToBalance(state) {
            const destinationToken = destinationTokenForSource(state.fromToken, state.destinationChainId);
            if (!destinationToken) {
                return "0";
            }
            return formatUnits(state.toBalance, destinationToken.decimals, 4);
        },
        formattedQuote(state) {
            const destinationToken = destinationTokenForSource(state.fromToken, state.destinationChainId);
            if (!state.quote || !destinationToken) {
                return "0";
            }
            return formatUnits(state.quote.amountOut, destinationToken.decimals, 6);
        },
        connectedWalletName(state) {
            if (!state.selectedWalletUuid) {
                return state.availableWallets[0]?.info.name ?? null;
            }
            return (state.availableWallets.find((wallet) => wallet.info.uuid === state.selectedWalletUuid)?.info.name ?? null);
        },
        walletRouteChainIds(state) {
            return routeChainIds(state.selectedChainId, state.destinationChainId);
        },
        walletChainSupported(state) {
            return isSupportedWalletChain(state.walletChainId);
        },
        walletNetworkActionPending(state) {
            return state.walletNetworkAction !== null;
        },
    },
    actions: {
        async initialize() {
            this.startDiscovery();
            if (this.selectedWalletUuid) {
                try {
                    await this.connectWallet(this.selectedWalletUuid);
                    return;
                }
                catch {
                    this.disconnectWallet();
                }
            }
            await this.refreshQuote();
        },
        startDiscovery() {
            if (typeof window === "undefined" || stopWalletDiscovery) {
                return;
            }
            stopWalletDiscovery = startWalletDiscovery((wallet) => {
                const existingWallet = this.availableWallets.find((entry) => entry.info.uuid === wallet.info.uuid);
                if (existingWallet) {
                    return;
                }
                this.availableWallets.push(wallet);
                this.availableWallets.sort((left, right) => left.info.name.localeCompare(right.info.name));
                if (!this.selectedWalletUuid) {
                    this.selectedWalletUuid = wallet.info.uuid;
                }
            });
        },
        async connectWallet(walletUuid) {
            const requestedWalletUuid = walletUuid ?? this.selectedWalletUuid ?? undefined;
            const wallet = this.availableWallets.find((entry) => entry.info.uuid === requestedWalletUuid) ??
                this.availableWallets[0];
            if (!wallet) {
                this.status = "error";
                this.statusMessage = "No EIP-6963 wallet was detected in this browser";
                return;
            }
            this.status = "connecting";
            this.statusMessage = `Connecting ${wallet.info.name}`;
            const accounts = await requestWalletAccounts(wallet.provider);
            if (accounts.length === 0) {
                this.status = "error";
                this.statusMessage = "The selected wallet returned no accounts";
                return;
            }
            stopWalletProviderSubscription?.();
            stopWalletProviderSubscription = subscribeWalletProvider(wallet.provider, {
                onAccountsChanged: (accountsChanged) => {
                    void this.handleAccountsChanged(accountsChanged);
                },
                onChainChanged: (chainIdHex) => {
                    void this.handleChainChanged(chainIdHex);
                },
                onDisconnect: () => {
                    this.disconnectWallet();
                },
            });
            this.selectedWalletUuid = wallet.info.uuid;
            this.walletAddress = accounts[0];
            this.walletConnected = true;
            this.walletChainId = await requestWalletChainId(wallet.provider);
            this.syncRouteWithWalletChain();
            storeWalletId(wallet.info.uuid);
            await this.refreshQuote();
        },
        disconnectWallet() {
            this.walletAddress = null;
            this.walletConnected = false;
            this.walletChainId = null;
            this.allowance = 0n;
            this.fromBalance = 0n;
            this.toBalance = 0n;
            this.quote = null;
            this.lastTxHash = null;
            this.walletNetworkAction = null;
            this.walletNetworkActionChainId = null;
            this.status = "idle";
            this.statusMessage = "Connect a wallet to prepare a bridge transfer";
            stopWalletProviderSubscription?.();
            stopWalletProviderSubscription = null;
            storeWalletId(null);
        },
        setWallet(walletUuid) {
            this.selectedWalletUuid = walletUuid;
        },
        async handleAccountsChanged(accounts) {
            if (accounts.length === 0) {
                this.disconnectWallet();
                return;
            }
            this.walletAddress = accounts[0];
            this.walletConnected = true;
            await this.refreshQuote();
        },
        async handleChainChanged(chainIdHex) {
            const chainId = chainIdHex.startsWith("0x")
                ? Number.parseInt(chainIdHex, 16)
                : Number(chainIdHex);
            this.walletChainId = Number.isInteger(chainId) ? chainId : null;
            this.syncRouteWithWalletChain();
            await this.refreshQuote();
        },
        syncRouteWithWalletChain() {
            if (!isSupportedWalletChain(this.walletChainId)) {
                return;
            }
            if (this.walletChainId === this.selectedChainId) {
                return;
            }
            this.updateRouteSourceChain(this.walletChainId);
        },
        updateRouteSourceChain(chainId) {
            const tokens = chainTokens(chainId);
            if (tokens.length === 0) {
                this.status = "error";
                this.statusMessage = `No tokens configured for chain ${chainId}`;
                return;
            }
            const nextDestinationChainId = this.destinationChainId === chainId ? this.selectedChainId : this.destinationChainId;
            const nextSourceToken = destinationTokenForSource(this.fromToken, chainId) ?? defaultSourceToken(chainId);
            this.selectedChainId = chainId;
            this.destinationChainId =
                nextDestinationChainId === chainId
                    ? defaultDestinationChainId(chainId)
                    : nextDestinationChainId;
            this.fromToken = nextSourceToken;
            this.quote = null;
            this.lastTxHash = null;
        },
        setChain(chainId) {
            this.updateRouteSourceChain(chainId);
            void this.refreshQuote();
        },
        async selectRouteSourceChain(chainId) {
            this.updateRouteSourceChain(chainId);
            await this.refreshQuote();
            if (!this.walletConnected || !this.walletAddress || !this.activeWallet) {
                return;
            }
            if (this.walletChainId === chainId) {
                return;
            }
            await this.switchWalletToChain(chainId);
        },
        setDestinationChain(chainId) {
            if (chainId === this.selectedChainId) {
                return;
            }
            this.destinationChainId = chainId;
            this.quote = null;
            this.lastTxHash = null;
            void this.refreshQuote();
        },
        setSourceToken(tokenAddress) {
            const token = chainTokens(this.selectedChainId).find((entry) => entry.address === tokenAddress) ?? null;
            if (!token) {
                return;
            }
            this.fromToken = token;
            this.quote = null;
            this.lastTxHash = null;
            void this.refreshQuote();
        },
        setAmount(text) {
            this.amountInText = text;
            this.lastTxHash = null;
        },
        swapDirection() {
            const nextSourceChainId = this.destinationChainId;
            const nextDestinationChainId = this.selectedChainId;
            const nextSourceToken = destinationTokenForSource(this.fromToken, nextSourceChainId) ??
                defaultSourceToken(nextSourceChainId);
            this.selectedChainId = nextSourceChainId;
            this.destinationChainId = nextDestinationChainId;
            this.fromToken = nextSourceToken;
            this.quote = null;
            this.lastTxHash = null;
            void this.refreshQuote();
        },
        async addChainToWallet(chainId) {
            if (!this.activeWallet) {
                this.status = "error";
                this.statusMessage = "Connect a wallet first";
                return;
            }
            this.walletNetworkAction = "adding-chain";
            this.walletNetworkActionChainId = chainId;
            this.statusMessage = `Adding ${chainLabel(chainId)} to the wallet`;
            try {
                await addWalletChain(this.activeWallet.provider, chainId);
                await this.refreshQuote();
            }
            catch (error) {
                this.status = "error";
                this.statusMessage = error instanceof Error ? error.message : String(error);
            }
            finally {
                this.walletNetworkAction = null;
                this.walletNetworkActionChainId = null;
            }
        },
        async addRouteChainsToWallet() {
            if (!this.activeWallet) {
                this.status = "error";
                this.statusMessage = "Connect a wallet first";
                return;
            }
            this.walletNetworkAction = "adding-route-chains";
            this.walletNetworkActionChainId = null;
            this.statusMessage = `Adding ${chainLabel(this.selectedChainId)} and ${chainLabel(this.destinationChainId)} to the wallet`;
            try {
                await addWalletRouteChains(this.activeWallet.provider, this.selectedChainId, this.destinationChainId);
                await this.refreshQuote();
            }
            catch (error) {
                this.status = "error";
                this.statusMessage = error instanceof Error ? error.message : String(error);
            }
            finally {
                this.walletNetworkAction = null;
                this.walletNetworkActionChainId = null;
            }
        },
        async switchWalletToChain(chainId) {
            if (!this.walletConnected || !this.walletAddress || !this.activeWallet) {
                throw new Error("Connect a wallet first");
            }
            if (this.walletChainId === chainId) {
                return;
            }
            this.walletNetworkAction = "switching-route-chain";
            this.walletNetworkActionChainId = chainId;
            this.status = "switching-chain";
            this.statusMessage = `Switching wallet to ${chainLabel(chainId)}`;
            try {
                await switchWalletChain(this.activeWallet.provider, chainId);
                this.walletChainId = await requestWalletChainId(this.activeWallet.provider);
                await this.refreshQuote();
            }
            catch (error) {
                this.status = "error";
                this.statusMessage = error instanceof Error ? error.message : String(error);
                throw error;
            }
            finally {
                this.walletNetworkAction = null;
                this.walletNetworkActionChainId = null;
            }
        },
        async ensureSelectedChain() {
            if (!this.walletConnected || !this.walletAddress || !this.activeWallet) {
                throw new Error("Connect a wallet first");
            }
            if (this.walletChainId === this.selectedChainId) {
                return;
            }
            await this.switchWalletToChain(this.selectedChainId);
        },
        async readBalanceForToken(token) {
            if (!this.walletAddress) {
                return 0n;
            }
            return readTokenBalance(this.walletAddress, token);
        },
        async refreshBalances() {
            if (!this.walletAddress) {
                this.fromBalance = 0n;
                this.toBalance = 0n;
                this.allowance = 0n;
                return;
            }
            const destinationToken = this.destinationToken;
            const [fromBalance, toBalance] = await Promise.all([
                readTokenBalance(this.walletAddress, this.fromToken),
                destinationToken
                    ? readTokenBalance(this.walletAddress, destinationToken)
                    : Promise.resolve(0n),
            ]);
            this.fromBalance = fromBalance;
            this.toBalance = toBalance;
            this.allowance = this.fromToken.isNative
                ? this.parsedAmountIn
                : await readTokenAllowance(this.walletAddress, this.fromToken, chainBridgeAddress(this.selectedChainId));
        },
        async refreshQuote() {
            if (!this.walletConnected || !this.walletAddress) {
                this.status = "idle";
                this.quote = null;
                this.statusMessage = "Connect a wallet to prepare a bridge transfer";
                this.fromBalance = 0n;
                this.toBalance = 0n;
                this.allowance = 0n;
                return;
            }
            const amountIn = this.parsedAmountIn;
            if (amountIn <= 0n) {
                this.status = "idle";
                this.quote = null;
                this.statusMessage = "Enter an amount to bridge";
                await this.refreshBalances();
                return;
            }
            const destinationToken = this.destinationToken;
            if (!destinationToken) {
                this.status = "error";
                this.quote = null;
                this.statusMessage = "No destination asset is configured for the selected route";
                await this.refreshBalances();
                return;
            }
            this.status = "quoting";
            this.statusMessage = "Preparing bridge route";
            try {
                this.quote = bridgePreview(this.selectedChainId, this.destinationChainId, amountIn);
                await this.refreshBalances();
                if (!this.fromToken.isNative && this.allowance < amountIn) {
                    this.status = "approval-required";
                    this.statusMessage = "Approve the bridge to move this token";
                    return;
                }
                this.status = "ready";
                this.statusMessage = "Bridge deposit is ready";
            }
            catch (error) {
                this.status = "error";
                this.statusMessage = error instanceof Error ? error.message : String(error);
            }
        },
        async approve() {
            if (!this.walletAddress || !this.activeWallet) {
                this.status = "error";
                this.statusMessage = "Connect a wallet first";
                return;
            }
            const amountIn = this.parsedAmountIn;
            if (amountIn <= 0n) {
                this.status = "error";
                this.statusMessage = "Amount must be greater than zero";
                return;
            }
            this.status = "approving";
            this.statusMessage = "Approval transaction pending";
            try {
                await this.ensureSelectedChain();
                const receipt = await approveBridgeToken(this.activeWallet.provider, this.walletAddress, this.fromToken, amountIn);
                this.lastTxHash = receipt.txHash;
                await this.refreshQuote();
            }
            catch (error) {
                this.status = "error";
                this.statusMessage = error instanceof Error ? error.message : String(error);
            }
        },
        async executeSwap() {
            if (!this.walletAddress || !this.activeWallet) {
                this.status = "error";
                this.statusMessage = "Connect a wallet first";
                return;
            }
            const amountIn = this.parsedAmountIn;
            if (amountIn <= 0n) {
                this.status = "error";
                this.statusMessage = "Amount must be greater than zero";
                return;
            }
            if (!this.destinationToken) {
                this.status = "error";
                this.statusMessage = "No destination asset is configured for this route";
                return;
            }
            this.status = "swapping";
            this.statusMessage = "Bridge deposit transaction pending";
            try {
                await this.ensureSelectedChain();
                const receipt = await depositToBridge(this.activeWallet.provider, this.walletAddress, this.selectedChainId, this.destinationChainId, this.fromToken, amountIn);
                this.lastTxHash = receipt.txHash;
                this.status = "success";
                this.statusMessage =
                    "Deposit confirmed. Track validator attestations and claim readiness below.";
                await this.refreshBalances();
                await this.refreshQuote();
            }
            catch (error) {
                this.status = "error";
                this.statusMessage = error instanceof Error ? error.message : String(error);
            }
        },
    },
});
