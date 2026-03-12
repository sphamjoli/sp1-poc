<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { useSwapStore } from "@/stores/swap";
import { claimBridgeTransfer } from "@/services/bridge";
import {
  fetchTransferRecords,
  markTransferRecordReceived,
} from "@/services/transfers";
import { formatDuration, formatTimestamp, shortenAddress } from "@/utils/format";
import { formatUnits } from "@/utils/amount";
import type { TransferRecord } from "@/types/transfers";

type ActivityFilter = "all" | "action" | "progress" | "done";

interface LocalClaimState {
  walletAddress: string;
  claimTimestamp: number;
  claimTransactionHash: string | null;
}

const LOCAL_CLAIMS_STORAGE_KEY = "bridge:local-claims";

const swapStore = useSwapStore();
const transferRecords = ref<TransferRecord[]>([]);
const loading = ref(false);
const errorMessage = ref("");
const claimErrorMessage = ref("");
const refreshedAt = ref<number | null>(null);
const activeFilter = ref<ActivityFilter>("all");
const claimingTransferId = ref<string | null>(null);
const localClaims = ref<Record<string, LocalClaimState>>(readStoredLocalClaims());
const nowSeconds = ref(Math.floor(Date.now() / 1000));
const claimStartedAt = ref<number | null>(null);
let refreshTimer: number | null = null;
let elapsedTimer: number | null = null;

const displayedTransfers = computed(() =>
  transferRecords.value.map((record) => {
    if (record.claimTransactionHash) {
      return record;
    }

    const localClaim = localClaims.value[record.id];
    if (!localClaim) {
      return record;
    }

    const connectedWallet = swapStore.walletAddress?.toLowerCase() ?? null;
    if (connectedWallet && connectedWallet !== localClaim.walletAddress) {
      return record;
    }

    return markTransferRecordReceived(
      record,
      localClaim.claimTimestamp,
      localClaim.claimTransactionHash,
    );
  }),
);
const readyTransfers = computed(() =>
  displayedTransfers.value.filter((record) => record.state === "claimable"),
);
const completedTransfers = computed(() =>
  displayedTransfers.value.filter((record) => record.state === "complete"),
);
const inProgressTransfers = computed(() =>
  displayedTransfers.value.filter(
    (record) => record.state === "attesting" || record.state === "pending",
  ),
);
const averageSettlementSeconds = computed(() => {
  if (completedTransfers.value.length === 0) {
    return null;
  }

  const total = completedTransfers.value.reduce((sum, record) => sum + record.durationSeconds, 0);
  return Math.round(total / completedTransfers.value.length);
});
const activityTabs = computed(
  () =>
    [
      {
        id: "all",
        label: "All transfers",
        count: transferRecords.value.length,
      },
      {
        id: "action",
        label: "Ready to receive",
        count: readyTransfers.value.length,
      },
      {
        id: "progress",
        label: "In progress",
        count: inProgressTransfers.value.length,
      },
      {
        id: "done",
        label: "Received",
        count: completedTransfers.value.length,
      },
    ] as const satisfies ReadonlyArray<{
      id: ActivityFilter;
      label: string;
      count: number;
    }>,
);
const visibleTransfers = computed(() => {
  switch (activeFilter.value) {
    case "action":
      return readyTransfers.value;
    case "progress":
      return inProgressTransfers.value;
    case "done":
      return completedTransfers.value;
    default:
      return displayedTransfers.value;
  }
});
const claimElapsedSeconds = computed(() =>
  claimStartedAt.value === null ? 0 : nowSeconds.value - claimStartedAt.value,
);

function readStoredLocalClaims(): Record<string, LocalClaimState> {
  if (typeof window === "undefined") {
    return {};
  }

  try {
    const rawValue = window.localStorage.getItem(LOCAL_CLAIMS_STORAGE_KEY);
    if (!rawValue) {
      return {};
    }

    const parsedValue = JSON.parse(rawValue) as Record<string, LocalClaimState>;
    return parsedValue && typeof parsedValue === "object" ? parsedValue : {};
  } catch {
    return {};
  }
}

function writeStoredLocalClaims(nextClaims: Record<string, LocalClaimState>): void {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.setItem(LOCAL_CLAIMS_STORAGE_KEY, JSON.stringify(nextClaims));
}

function setLocalClaimState(
  record: TransferRecord,
  walletAddress: string,
  claimTransactionHash: string | null,
  claimTimestamp: number,
): void {
  const nextClaims = {
    ...localClaims.value,
    [record.id]: {
      walletAddress: walletAddress.toLowerCase(),
      claimTransactionHash,
      claimTimestamp,
    },
  } satisfies Record<string, LocalClaimState>;

  localClaims.value = nextClaims;
  writeStoredLocalClaims(nextClaims);
}

function clearSyncedLocalClaims(records: TransferRecord[]): void {
  const syncedIds = new Set(
    records.filter((record) => Boolean(record.claimTransactionHash)).map((record) => record.id),
  );

  if (syncedIds.size === 0) {
    return;
  }

  const nextClaims = Object.fromEntries(
    Object.entries(localClaims.value).filter(([recordId]) => !syncedIds.has(recordId)),
  );

  localClaims.value = nextClaims;
  writeStoredLocalClaims(nextClaims);
}

function isAlreadyClaimedError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  const normalizedMessage = message.toLowerCase();
  return normalizedMessage.includes("alreadyclaimed") || normalizedMessage.includes("already claimed");
}

function stateBadgeClass(state: TransferRecord["state"]): string {
  if (state === "complete") {
    return "bg-emerald-400/15 text-emerald-200";
  }

  if (state === "claimable") {
    return "bg-cyan-300/15 text-cyan-100";
  }

  if (state === "attesting") {
    return "bg-amber-400/15 text-amber-100";
  }

  return "bg-white/8 text-white/60";
}

function progressWidth(state: TransferRecord["state"]): string {
  if (state === "complete") {
    return "100%";
  }

  if (state === "claimable") {
    return "84%";
  }

  if (state === "attesting") {
    return "58%";
  }

  return "24%";
}

function outgoingBalanceLabel(record: TransferRecord): string {
  return `-${formatUnits(record.amount, record.assetDecimals, 4)} ${record.assetSymbol}`;
}

function incomingBalanceLabel(record: TransferRecord): string {
  return `+${formatUnits(record.amount, record.assetDecimals, 4)} ${record.assetSymbol}`;
}

function incomingBalanceNote(record: TransferRecord): string {
  if (record.state === "complete") {
    return `Received on ${record.destinationChainLabel}.`;
  }

  if (record.state === "claimable") {
    return `Ready to receive on ${record.destinationChainLabel} now.`;
  }

  if (record.state === "attesting") {
    return `Will arrive on ${record.destinationChainLabel} after checks finish.`;
  }

  return `Waiting for the first checks on ${record.destinationChainLabel}.`;
}

function claimButtonLabel(record: TransferRecord): string {
  if (claimingTransferId.value === record.id) {
    return "Receiving";
  }

  if (swapStore.walletChainId === record.destinationChainId) {
    return "Receive funds";
  }

  return `Switch to ${record.destinationChainLabel} and receive`;
}

async function refreshTransferRecords(): Promise<void> {
  if (!swapStore.walletAddress) {
    transferRecords.value = [];
    loading.value = false;
    errorMessage.value = "";
    claimErrorMessage.value = "";
    refreshedAt.value = null;
    return;
  }

  loading.value = true;
  errorMessage.value = "";

  try {
    transferRecords.value = await fetchTransferRecords(swapStore.walletAddress, {
      limit: 50,
      attestationLimit: 300,
    });
    clearSyncedLocalClaims(transferRecords.value);
    refreshedAt.value = Math.floor(Date.now() / 1000);
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : String(error);
  } finally {
    loading.value = false;
  }
}

async function receiveTransfer(record: TransferRecord): Promise<void> {
  if (!swapStore.walletAddress || !swapStore.activeWallet) {
    claimErrorMessage.value = "Connect the receiving wallet first.";
    return;
  }

  claimErrorMessage.value = "";
  claimingTransferId.value = record.id;
  claimStartedAt.value = Math.floor(Date.now() / 1000);

  try {
    if (swapStore.walletChainId !== record.destinationChainId) {
      await swapStore.switchWalletToChain(record.destinationChainId);
    }

    const receipt = await claimBridgeTransfer(
      swapStore.activeWallet.provider,
      swapStore.walletAddress,
      record,
    );
    const claimTimestamp = Math.floor(Date.now() / 1000);

    setLocalClaimState(record, swapStore.walletAddress, receipt.txHash, claimTimestamp);
    transferRecords.value = transferRecords.value.map((entry) =>
      entry.id === record.id
        ? markTransferRecordReceived(entry, claimTimestamp, receipt.txHash)
        : entry,
    );

    swapStore.lastTxHash = receipt.txHash;
    swapStore.statusMessage = "Funds received. Balances and transfer progress are updating.";
    await Promise.all([swapStore.refreshBalances(), refreshTransferRecords()]);
  } catch (error) {
    if (isAlreadyClaimedError(error) && swapStore.walletAddress) {
      const claimTimestamp = Math.floor(Date.now() / 1000);
      setLocalClaimState(record, swapStore.walletAddress, record.claimTransactionHash, claimTimestamp);
      transferRecords.value = transferRecords.value.map((entry) =>
        entry.id === record.id
          ? markTransferRecordReceived(entry, claimTimestamp, entry.claimTransactionHash)
          : entry,
      );
      claimErrorMessage.value = "";
      swapStore.statusMessage = "Funds were already received. Waiting for activity sync.";
      await Promise.all([swapStore.refreshBalances(), refreshTransferRecords()]);
      return;
    }

    claimErrorMessage.value = error instanceof Error ? error.message : String(error);
  } finally {
    claimingTransferId.value = null;
    claimStartedAt.value = null;
  }
}

watch(
  () => swapStore.walletAddress,
  async () => {
    await refreshTransferRecords();
  },
);

watch(
  () => swapStore.lastTxHash,
  async () => {
    await refreshTransferRecords();
  },
);

onMounted(async () => {
  await refreshTransferRecords();
  refreshTimer = window.setInterval(async () => {
    await refreshTransferRecords();
  }, 5000);
  elapsedTimer = window.setInterval(() => {
    nowSeconds.value = Math.floor(Date.now() / 1000);
  }, 1000);
});

onUnmounted(() => {
  if (refreshTimer !== null) {
    window.clearInterval(refreshTimer);
  }

  if (elapsedTimer !== null) {
    window.clearInterval(elapsedTimer);
  }
});
</script>

<template>
  <section class="overflow-hidden rounded-[32px] border border-white/10 bg-white/[0.045] shadow-[0_32px_120px_rgba(0,0,0,0.34)] backdrop-blur-xl">
    <div class="border-b border-white/8 px-5 py-4 sm:px-6">
      <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p class="text-xs uppercase tracking-[0.28em] text-white/45">Activity</p>
          <h2 class="mt-2 font-display text-2xl font-semibold text-white">Transfer progress</h2>
          <p class="mt-1 text-sm text-white/55">
            See what has already left, what is still moving, and what is ready to receive.
          </p>
        </div>

        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div class="rounded-2xl border border-white/8 bg-black/20 px-3 py-3">
            <p class="text-[11px] uppercase tracking-[0.2em] text-white/40">Ready</p>
            <p class="mt-2 text-xl font-semibold text-cyan-100">{{ readyTransfers.length }}</p>
          </div>
          <div class="rounded-2xl border border-white/8 bg-black/20 px-3 py-3">
            <p class="text-[11px] uppercase tracking-[0.2em] text-white/40">In progress</p>
            <p class="mt-2 text-xl font-semibold text-white">{{ inProgressTransfers.length }}</p>
          </div>
          <div class="rounded-2xl border border-white/8 bg-black/20 px-3 py-3">
            <p class="text-[11px] uppercase tracking-[0.2em] text-white/40">Received</p>
            <p class="mt-2 text-xl font-semibold text-emerald-200">{{ completedTransfers.length }}</p>
          </div>
          <div class="rounded-2xl border border-white/8 bg-black/20 px-3 py-3">
            <p class="text-[11px] uppercase tracking-[0.2em] text-white/40">Avg time</p>
            <p class="mt-2 text-xl font-semibold text-white">
              {{ averageSettlementSeconds ? formatDuration(averageSettlementSeconds) : '-' }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <div class="px-5 py-5 sm:px-6">
      <div class="mb-4 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div class="flex flex-wrap gap-2">
          <button
            v-for="tab in activityTabs"
            :key="tab.id"
            type="button"
            class="rounded-full border px-3 py-2 text-sm transition"
            :class="activeFilter === tab.id
              ? 'border-cyan-300/35 bg-cyan-300/10 text-cyan-50'
              : 'border-white/10 bg-white/5 text-white/60 hover:border-white/20 hover:text-white'"
            @click="activeFilter = tab.id"
          >
            {{ tab.label }} · {{ tab.count }}
          </button>
        </div>

        <div class="flex items-center justify-between gap-3 text-xs text-white/40">
          <span v-if="refreshedAt">Updated {{ formatTimestamp(refreshedAt) }}</span>
          <span v-else>Waiting for first transfer sync</span>
          <button
            type="button"
            class="rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-white/65 transition hover:border-cyan-300/30 hover:text-white"
            @click="refreshTransferRecords"
          >
            Refresh
          </button>
        </div>
      </div>

      <div
        v-if="claimErrorMessage"
        class="mb-4 rounded-3xl border border-rose-500/20 bg-rose-500/10 px-4 py-4 text-sm text-rose-100"
      >
        {{ claimErrorMessage }}
      </div>

      <div v-if="loading && transferRecords.length === 0" class="space-y-3">
        <div v-for="index in 3" :key="index" class="h-40 animate-pulse rounded-3xl border border-white/8 bg-white/5" />
      </div>

      <div v-else-if="errorMessage" class="rounded-3xl border border-rose-500/20 bg-rose-500/10 px-4 py-4 text-sm text-rose-100">
        {{ errorMessage }}
      </div>

      <div v-else-if="transferRecords.length === 0" class="rounded-3xl border border-dashed border-white/12 bg-black/20 px-6 py-12 text-center">
        <p class="font-display text-xl font-semibold text-white">
          {{ swapStore.walletConnected ? 'No transfers yet' : 'Wallet connection required' }}
        </p>
        <p class="mt-2 text-sm text-white/45">
          {{ swapStore.walletConnected
            ? 'Transfers will appear here after deposits are indexed for this wallet.'
            : 'Connect a wallet to load transfers and see when funds are ready to receive.' }}
        </p>
      </div>

      <div v-else-if="visibleTransfers.length === 0" class="rounded-3xl border border-dashed border-white/12 bg-black/20 px-6 py-12 text-center">
        <p class="font-display text-xl font-semibold text-white">Nothing in this tab right now</p>
        <p class="mt-2 text-sm text-white/45">Try another activity tab or refresh the transfer list.</p>
      </div>

      <div v-else class="space-y-3">
        <article
          v-for="record in visibleTransfers"
          :key="record.id"
          class="rounded-3xl border border-white/8 bg-black/25 p-4 transition hover:border-cyan-300/25 hover:bg-black/35"
        >
          <div class="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-2">
                <span class="rounded-full border border-white/10 bg-white/5 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.24em] text-white/50">
                  {{ record.assetSymbol }}
                </span>
                <span class="rounded-full px-3 py-1 text-xs font-semibold" :class="stateBadgeClass(record.state)">
                  {{ record.stateLabel }}
                </span>
                <span class="text-xs text-white/35">{{ formatTimestamp(record.depositTimestamp) }}</span>
              </div>

              <div class="mt-4 flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
                <div>
                  <p class="font-display text-2xl font-semibold text-white">
                    {{ formatUnits(record.amount, record.assetDecimals, 4) }} {{ record.assetSymbol }}
                  </p>
                  <p class="mt-1 text-sm text-white/50">
                    {{ record.sourceChainLabel }} to {{ record.destinationChainLabel }}
                  </p>
                </div>

                <div class="flex flex-wrap gap-4 text-sm text-white/50">
                  <div>
                    <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Time so far</p>
                    <p class="mt-1 font-semibold text-white">{{ formatDuration(record.durationSeconds) }}</p>
                  </div>
                  <div>
                    <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Checks complete</p>
                    <p class="mt-1 font-semibold text-white">{{ record.attestationCount }}</p>
                  </div>
                </div>
              </div>

              <div class="mt-4 h-2 overflow-hidden rounded-full bg-white/8">
                <div
                  class="h-full rounded-full bg-gradient-to-r from-emerald-400 via-cyan-400 to-amber-300"
                  :style="{ width: progressWidth(record.state) }"
                />
              </div>

              <div class="mt-4 grid gap-3 text-sm md:grid-cols-2">
                <div
                  v-if="record.walletIsSender"
                  class="rounded-3xl border border-white/8 bg-white/[0.03] p-4 text-white/65"
                >
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Money left</p>
                  <p class="mt-2 text-lg font-semibold text-rose-200">
                    {{ outgoingBalanceLabel(record) }}
                  </p>
                  <p class="mt-1 text-xs text-white/45">
                    Left {{ record.sourceChainLabel }} when the deposit was confirmed.
                  </p>
                </div>

                <div
                  v-if="record.walletIsRecipient"
                  class="rounded-3xl border border-white/8 bg-white/[0.03] p-4 text-white/65"
                >
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Money arriving</p>
                  <p class="mt-2 text-lg font-semibold text-emerald-200">
                    {{ incomingBalanceLabel(record) }}
                  </p>
                  <p class="mt-1 text-xs text-white/45">{{ incomingBalanceNote(record) }}</p>
                </div>
              </div>

              <div class="mt-4 grid gap-3 text-sm text-white/50 md:grid-cols-2 xl:grid-cols-4">
                <div>
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Status</p>
                  <p class="mt-1 text-white">{{ record.detailLabel }}</p>
                </div>
                <div>
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Sent by</p>
                  <p class="mt-1 font-mono text-white/70">{{ shortenAddress(record.sender, 5) }}</p>
                </div>
                <div>
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Receiving wallet</p>
                  <p class="mt-1 font-mono text-white/70">{{ shortenAddress(record.recipient, 5) }}</p>
                </div>
                <div>
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Deposit tx</p>
                  <p class="mt-1 font-mono text-white/70">{{ shortenAddress(record.depositTransactionHash, 6) }}</p>
                </div>
              </div>

              <div v-if="record.claimTransactionHash || record.claimTimestamp" class="mt-4 grid gap-3 text-sm text-white/50 md:grid-cols-2">
                <div v-if="record.claimTransactionHash">
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Receive tx</p>
                  <p class="mt-1 font-mono text-white/70">{{ shortenAddress(record.claimTransactionHash, 6) }}</p>
                </div>
                <div v-if="record.claimTimestamp">
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Received at</p>
                  <p class="mt-1 text-white">{{ formatTimestamp(record.claimTimestamp) }}</p>
                </div>
              </div>
            </div>

            <div v-if="record.state === 'claimable'" class="xl:ml-4 xl:w-64">
              <div class="rounded-3xl border border-cyan-300/20 bg-cyan-300/10 p-4">
                <p class="text-sm font-semibold text-cyan-50">Funds are ready</p>
                <p class="mt-2 text-sm text-cyan-50/80">
                  Receive on {{ record.destinationChainLabel }} to finish this transfer.
                </p>
                <div
                  v-if="claimingTransferId === record.id"
                  class="mt-4 rounded-2xl border border-cyan-200/20 bg-cyan-950/20 p-3 text-cyan-50/80"
                >
                  <div class="flex items-start gap-3">
                    <div class="mt-1 h-4 w-4 animate-spin rounded-full border-2 border-cyan-100 border-t-transparent" />
                    <div>
                      <p class="text-sm font-semibold text-cyan-50">Waiting for the receive transaction</p>
                      <p class="mt-1 text-xs">
                        Check the wallet popup if it is still open. This screen updates automatically.
                      </p>
                      <p class="mt-2 text-xs">
                        Waiting {{ formatDuration(Math.max(claimElapsedSeconds, 1)) }}
                      </p>
                      <p v-if="claimElapsedSeconds >= 20" class="mt-2 text-xs text-cyan-50/70">
                        This can take a while. Keep this page open until the transfer moves to Received.
                      </p>
                    </div>
                  </div>
                </div>
                <button
                  type="button"
                  class="mt-4 w-full rounded-2xl bg-cyan-300 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="claimingTransferId !== null"
                  @click="receiveTransfer(record)"
                >
                  {{ claimButtonLabel(record) }}
                </button>
              </div>
            </div>
          </div>
        </article>
      </div>
    </div>
  </section>
</template>
