import { type Address } from "viem";
import type { TokenInfo, QuoteResult, SwapExecution } from "@/types/swap";
import type { TransferRecord } from "@/types/transfers";
import type { Eip1193Provider } from "@/types/wallet";
interface ClaimabilityResult {
    claimable: boolean;
    stateRoot: `0x${string}`;
}
export declare function sourceChainTokens(chainId: number): TokenInfo[];
export declare function destinationTokenForSource(sourceToken: TokenInfo, destinationChainId: number): TokenInfo | null;
export declare function requestWalletAccounts(provider: Eip1193Provider): Promise<Address[]>;
export declare function requestWalletChainId(provider: Eip1193Provider): Promise<number>;
export declare function readTokenBalance(walletAddress: Address, token: TokenInfo): Promise<bigint>;
export declare function readTokenAllowance(walletAddress: Address, token: TokenInfo, spender: Address): Promise<bigint>;
export declare function approveBridgeToken(provider: Eip1193Provider, walletAddress: Address, token: TokenInfo, amount: bigint): Promise<SwapExecution>;
export declare function depositToBridge(provider: Eip1193Provider, walletAddress: Address, sourceChainId: number, destinationChainId: number, token: TokenInfo, amount: bigint): Promise<SwapExecution>;
export declare function bridgePreview(sourceChainId: number, destinationChainId: number, amountIn: bigint): QuoteResult;
export declare function chainBridgeAddress(chainId: number): Address;
export declare function readBlockStateRoot(chainId: number, blockNumber: number): Promise<`0x${string}`>;
export declare function isBridgeTransferClaimable(record: Pick<TransferRecord, "destinationChainId" | "sourceBlockNumber" | "sourceChainId" | "sourceRoot">): Promise<ClaimabilityResult>;
export declare function claimBridgeTransfer(provider: Eip1193Provider, walletAddress: Address, record: Pick<TransferRecord, "amount" | "depositIndex" | "destinationChainId" | "recipient" | "sourceBlockNumber" | "sourceChainId" | "sourceRoot" | "sourceStateRoot" | "sourceTokenAddress">): Promise<SwapExecution>;
export {};
