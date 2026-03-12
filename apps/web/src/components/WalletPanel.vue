<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { SUPPORTED_CHAINS, chainLabel } from "@/config/networks";
import {
  destinationTokenForSource,
  sourceChainTokens,
} from "@/services/bridge";
import { fetchTransferRecords } from "@/services/transfers";
import { useSwapStore } from "@/stores/swap";
import type { TokenInfo } from "@/types/swap";
import type { TransferRecord } from "@/types/transfers";
import { formatUnits } from "@/utils/amount";
import { formatTimestamp, shortenAddress } from "@/utils/format";

interface MovementTotals {
  sent: bigint;
  received: bigint;
  waiting: bigint;
}

interface TokenBalanceRow extends MovementTotals {
  token: TokenInfo;
  balance: bigint;
}

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const swapStore = useSwapStore();
const balanceRows = ref<TokenBalanceRow[]>([]);
const transferRecords = ref<TransferRecord[]>([]);
const loading = ref(false);
const errorMessage = ref("");
const lastSyncedAt = ref<number | null>(null);
let refreshTimer: number | null = null;

const walletLabel = computed(() =>
  swapStore.walletAddress ? shortenAddress(swapStore.walletAddress, 5) : "Not connected",
);
const sentTransferCount = computed(
  () => transferRecords.value.filter((record) => record.walletIsSender).length,
);
const receivedTransferCount = computed(
  () =>
    transferRecords.value.filter(
      (record) => record.walletIsRecipient && record.claimTransactionHash !== null,
    ).length,
);
const waitingTransferCount = computed(
  () =>
    transferRecords.value.filter(
      (record) => record.walletIsRecipient && record.claimTransactionHash === null,
    ).length,
);
const chainSections = computed(() =>
  SUPPORTED_CHAINS.map((chain) => ({
    chainId: chain.id,
    chainLabel: chainLabel(chain.id),
    rows: balanceRows.value
      .filter(
        (row) =>
          row.token.chainId === chain.id &&
          (row.balance > 0n || row.sent > 0n || row.received > 0n || row.waiting > 0n),
      )
      .sort((left, right) => {
        if (left.token.isNative !== right.token.isNative) {
          return left.token.isNative ? -1 : 1;
        }

        const leftActivity = left.sent + left.received + left.waiting;
        const rightActivity = right.sent + right.received + right.waiting;
        if (leftActivity !== rightActivity) {
          return leftActivity > rightActivity ? -1 : 1;
        }

        if (left.balance !== right.balance) {
          return left.balance > right.balance ? -1 : 1;
        }

        return left.token.symbol.localeCompare(right.token.symbol);
      }),
  })),
);

function normalizeAddress(value: string): string {
  return value.toLowerCase();
}

function tokenKey(chainId: number, address: string): string {
  return `${chainId}:${normalizeAddress(address)}`;
}

function sourceTokenForRecord(record: TransferRecord): TokenInfo | null {
  return (
    sourceChainTokens(record.sourceChainId).find(
      (token) =>
        token.address.toLowerCase() === record.sourceTokenAddress.toLowerCase(),
    ) ?? null
  );
}

function destinationTokenForRecord(record: TransferRecord): TokenInfo | null {
  const sourceToken = sourceTokenForRecord(record);
  if (sourceToken) {
    return destinationTokenForSource(sourceToken, record.destinationChainId);
  }

  if (normalizeAddress(record.sourceTokenAddress) === ZERO_ADDRESS) {
    return (
      sourceChainTokens(record.destinationChainId).find((token) => token.isNative) ?? null
    );
  }

  return null;
}

function formatTokenAmount(value: bigint, token: TokenInfo): string {
  return formatUnits(value, token.decimals, 4);
}

function buildMovementTotals(records: TransferRecord[]): Map<string, MovementTotals> {
  const totalsByKey = new Map<string, MovementTotals>();

  function ensureTotals(key: string): MovementTotals {
    const existingTotals = totalsByKey.get(key);
    if (existingTotals) {
      return existingTotals;
    }

    const nextTotals = { sent: 0n, received: 0n, waiting: 0n };
    totalsByKey.set(key, nextTotals);
    return nextTotals;
  }

  for (const record of records) {
    if (record.walletIsSender) {
      const sourceKey = tokenKey(record.sourceChainId, record.sourceTokenAddress);
      ensureTotals(sourceKey).sent += record.amount;
    }

    if (!record.walletIsRecipient) {
      continue;
    }

    const destinationToken = destinationTokenForRecord(record);
    if (!destinationToken) {
      continue;
    }

    const destinationKey = tokenKey(destinationToken.chainId, destinationToken.address);
    const totals = ensureTotals(destinationKey);

    if (record.claimTransactionHash) {
      totals.received += record.amount;
    } else {
      totals.waiting += record.amount;
    }
  }

  return totalsByKey;
}

async function refreshWalletData(): Promise<void> {
  if (!swapStore.walletAddress) {
    balanceRows.value = [];
    transferRecords.value = [];
    errorMessage.value = "";
    loading.value = false;
    lastSyncedAt.value = null;
    return;
  }

  loading.value = true;
  errorMessage.value = "";

  try {
    const trackedTokens = SUPPORTED_CHAINS.flatMap((chain) => sourceChainTokens(chain.id));
    const [balances, records] = await Promise.all([
      Promise.all(
        trackedTokens.map(async (token) => ({
          token,
          balance: await swapStore.readBalanceForToken(token),
        })),
      ),
      fetchTransferRecords(swapStore.walletAddress, {
        limit: 100,
        attestationLimit: 300,
        includeRuntimeState: false,
      }),
    ]);

    transferRecords.value = records;
    const movementByKey = buildMovementTotals(records);

    balanceRows.value = balances.map(({ token, balance }) => {
      const totals = movementByKey.get(tokenKey(token.chainId, token.address)) ?? {
        sent: 0n,
        received: 0n,
        waiting: 0n,
      };

      return {
        token,
        balance,
        sent: totals.sent,
        received: totals.received,
        waiting: totals.waiting,
      } satisfies TokenBalanceRow;
    });
    lastSyncedAt.value = Math.floor(Date.now() / 1000);
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : String(error);
  } finally {
    loading.value = false;
  }
}

watch(
  () => swapStore.walletAddress,
  async () => {
    await refreshWalletData();
  },
);

watch(
  () => swapStore.lastTxHash,
  async () => {
    await refreshWalletData();
  },
);

onMounted(async () => {
  await refreshWalletData();
  refreshTimer = window.setInterval(async () => {
    await refreshWalletData();
  }, 5000);
});

onUnmounted(() => {
  if (refreshTimer !== null) {
    window.clearInterval(refreshTimer);
  }
});
</script>

<template>
  <section class="overflow-hidden rounded-[28px] border border-white/10 bg-white/[0.045] shadow-[0_24px_90px_rgba(0,0,0,0.28)] backdrop-blur-xl">
    <div class="border-b border-white/8 px-5 py-4 sm:px-6">
      <div class="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p class="text-xs uppercase tracking-[0.28em] text-white/45">Balances</p>
          <h2 class="mt-2 font-display text-2xl font-semibold text-white">Your money by chain</h2>
          <p class="mt-1 text-sm text-white/55">
            Showing assets with a balance or bridge activity, plus what was sent, received, or is still on the way.
          </p>
        </div>
        <div class="rounded-full border border-white/10 bg-white/5 px-3 py-2 text-xs text-white/55">
          <span v-if="lastSyncedAt">Synced {{ formatTimestamp(lastSyncedAt) }}</span>
          <span v-else>Connect a wallet to load balances</span>
        </div>
      </div>
    </div>

    <div class="px-5 py-5 sm:px-6">
      <div class="mb-4 grid gap-3 lg:grid-cols-[minmax(0,1fr)_180px_180px_180px]">
        <div class="rounded-3xl border border-white/8 bg-black/25 p-4">
          <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Wallet</p>
          <p class="mt-2 font-mono text-sm text-white/80">{{ walletLabel }}</p>
          <p class="mt-1 text-xs text-white/45">Bridge movement is calculated from indexed history.</p>
        </div>

        <div class="rounded-3xl border border-white/8 bg-black/25 p-4">
          <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Sent</p>
          <p class="mt-2 font-display text-3xl font-semibold text-rose-200">{{ sentTransferCount }}</p>
          <p class="mt-1 text-xs text-white/45">Transfers that left this wallet</p>
        </div>

        <div class="rounded-3xl border border-white/8 bg-black/25 p-4">
          <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Received</p>
          <p class="mt-2 font-display text-3xl font-semibold text-emerald-200">{{ receivedTransferCount }}</p>
          <p class="mt-1 text-xs text-white/45">Transfers that arrived</p>
        </div>

        <div class="rounded-3xl border border-white/8 bg-black/25 p-4">
          <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Waiting</p>
          <p class="mt-2 font-display text-3xl font-semibold text-cyan-100">{{ waitingTransferCount }}</p>
          <p class="mt-1 text-xs text-white/45">Transfers still moving</p>
        </div>
      </div>

      <div
        v-if="!swapStore.walletConnected"
        class="rounded-3xl border border-dashed border-white/12 bg-black/20 px-6 py-12 text-center"
      >
        <p class="font-display text-xl font-semibold text-white">Wallet connection required</p>
        <p class="mt-2 text-sm text-white/45">
          Connect a wallet to see balances and bridge movement across the supported chains.
        </p>
      </div>

      <div v-else-if="loading && balanceRows.length === 0" class="grid gap-4 xl:grid-cols-2">
        <div v-for="index in 2" :key="index" class="h-60 animate-pulse rounded-3xl border border-white/8 bg-white/5" />
      </div>

      <div v-else-if="errorMessage" class="rounded-3xl border border-rose-500/20 bg-rose-500/10 px-4 py-4 text-sm text-rose-100">
        {{ errorMessage }}
      </div>

      <div v-else class="grid gap-4 xl:grid-cols-2">
        <article
          v-for="section in chainSections"
          :key="section.chainId"
          class="rounded-3xl border border-white/8 bg-black/25 p-4"
        >
          <div class="flex flex-col gap-3 border-b border-white/8 pb-4 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <p class="font-display text-2xl font-semibold text-white">{{ section.chainLabel }}</p>
              <p class="mt-1 text-sm text-white/45">Current balance and bridge movement on this chain.</p>
            </div>

            <div class="flex flex-wrap gap-2 text-[11px] uppercase tracking-[0.18em]">
              <span
                v-if="swapStore.walletChainId === section.chainId"
                class="rounded-full border border-cyan-300/25 bg-cyan-300/10 px-2.5 py-1 text-cyan-50"
              >
                Wallet active
              </span>
              <span
                v-if="swapStore.selectedChainId === section.chainId"
                class="rounded-full border border-white/10 bg-white/5 px-2.5 py-1 text-white/65"
              >
                Deposit chain
              </span>
            </div>
          </div>

          <div v-if="section.rows.length === 0" class="pt-4 text-sm text-white/45">
            No balance or bridge movement on this chain yet.
          </div>

          <div v-else class="mt-4 space-y-3">
            <div
              v-for="row in section.rows"
              :key="`${row.token.chainId}:${row.token.address}`"
              class="rounded-3xl border border-white/8 bg-white/[0.03] p-4"
            >
              <div class="flex flex-col gap-4">
                <div>
                  <div class="flex flex-wrap items-center gap-2">
                    <p class="text-sm font-semibold text-white">{{ row.token.symbol }}</p>
                    <span class="rounded-full border border-white/10 bg-white/5 px-2 py-0.5 text-[10px] uppercase tracking-[0.18em] text-white/45">
                      {{ row.token.isNative ? 'native' : 'token' }}
                    </span>
                  </div>
                  <p class="mt-1 text-xs text-white/45">{{ row.token.name }}</p>
                </div>

                <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                  <div class="rounded-2xl border border-white/8 bg-black/20 px-3 py-3">
                    <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Available now</p>
                    <p class="mt-1 text-lg font-semibold text-white">{{ formatTokenAmount(row.balance, row.token) }}</p>
                  </div>

                  <div class="rounded-2xl border border-white/8 bg-black/20 px-3 py-3">
                    <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Sent out</p>
                    <p class="mt-1 text-lg font-semibold text-rose-200">{{ formatTokenAmount(row.sent, row.token) }}</p>
                  </div>

                  <div class="rounded-2xl border border-white/8 bg-black/20 px-3 py-3">
                    <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Received</p>
                    <p class="mt-1 text-lg font-semibold text-emerald-200">{{ formatTokenAmount(row.received, row.token) }}</p>
                  </div>

                  <div class="rounded-2xl border border-white/8 bg-black/20 px-3 py-3">
                    <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Still coming</p>
                    <p class="mt-1 text-lg font-semibold text-cyan-100">{{ formatTokenAmount(row.waiting, row.token) }}</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </article>
      </div>
    </div>
  </section>
</template>
