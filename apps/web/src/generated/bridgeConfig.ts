import type { TokenInfo } from "@/types/swap";

export interface SupportedChain {
  id: number;
  name: string;
  rpcUrl: string;
  bridge: `0x${string}`;
  validatorManager: `0x${string}`;
}

export const SUPPORTED_CHAINS: SupportedChain[] = [
  {
    "id": 31338,
    "name": "Ethereum",
    "rpcUrl": "http://127.0.0.1:8545",
    "bridge": "0x10D324b02B2d5D998aeCec99038b956F9875cFDE",
    "validatorManager": "0xe374A6bfA2058357d7BCbC22107941e4A3F87749"
  },
  {
    "id": 31339,
    "name": "Base",
    "rpcUrl": "http://127.0.0.1:8546",
    "bridge": "0xa513E6E4b8f2a923D98304ec87F64353C4D5C853",
    "validatorManager": "0xB7f8BC63BbcaD18155201308C8f3540b07f84F5e"
  }
] as SupportedChain[];

export const CHAIN_LABELS: Record<number, string> = {
  "31338": "Ethereum",
  "31339": "Base"
};

export const SUPPORTED_TOKENS: TokenInfo[] = [
  {
    "chainId": 31338,
    "address": "0x0000000000000000000000000000000000000000",
    "symbol": "ETH",
    "name": "Ethereum Native Ether",
    "decimals": 18,
    "isNative": true
  },
  {
    "chainId": 31338,
    "address": "0x9aa38E44d1349BC84c918feb03d42B7c0c99240C",
    "symbol": "EBTA",
    "name": "Ethereum Bridge Token A",
    "decimals": 18,
    "isNative": false
  },
  {
    "chainId": 31338,
    "address": "0xFD36547588df18d7AF89e56Fe95E7EeC9F0C6b54",
    "symbol": "EBTB",
    "name": "Ethereum Bridge Token B",
    "decimals": 18,
    "isNative": false
  },
  {
    "chainId": 31339,
    "address": "0x0000000000000000000000000000000000000000",
    "symbol": "ETH",
    "name": "Base Native Ether",
    "decimals": 18,
    "isNative": true
  },
  {
    "chainId": 31339,
    "address": "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
    "symbol": "BBTA",
    "name": "Base Bridge Token A",
    "decimals": 18,
    "isNative": false
  },
  {
    "chainId": 31339,
    "address": "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9",
    "symbol": "BBTB",
    "name": "Base Bridge Token B",
    "decimals": 18,
    "isNative": false
  }
] as TokenInfo[];

export const DEFAULT_CHAIN_ID = 31338;

export const SWAP_SPENDER: `0x${string}` = "0x1111111111111111111111111111111111111111";
