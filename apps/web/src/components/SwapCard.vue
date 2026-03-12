<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { useSwapStore } from "@/stores/swap";
import { sourceChainTokens } from "@/services/bridge";
import { SUPPORTED_CHAINS } from "@/generated/bridgeConfig";
import { chainLabel } from "@/config/networks";
import { formatUnits } from "@/utils/amount";
import { formatDuration, shortenAddress } from "@/utils/format";

const swapStore = useSwapStore();

const sourceTokens = computed(() => sourceChainTokens(swapStore.selectedChainId));
const destinationToken = computed(() => swapStore.destinationToken);
const walletLabel = computed(() =>
  swapStore.walletAddress ? shortenAddress(swapStore.walletAddress, 5) : "No wallet",
);
const sourceChainLabel = computed(() => chainLabel(swapStore.selectedChainId));
const destinationChainLabel = computed(() => chainLabel(swapStore.destinationChainId));
const walletChainLabel = computed(() =>
  swapStore.walletChainId ? chainLabel(swapStore.walletChainId) : "No active network",
);
const showNetworkPicker = ref(false);
const nowSeconds = ref(Math.floor(Date.now() / 1000));
const pendingStartedAt = ref<number | null>(null);
let pendingTimer: number | null = null;
const routeChainActions = computed(() =>
  swapStore.walletRouteChainIds.map((chainId) => ({
    chainId,
    label: chainLabel(chainId),
    isSelectedSource: swapStore.selectedChainId === chainId,
    isWalletActive: swapStore.walletChainId === chainId,
    isPending: swapStore.walletNetworkActionChainId === chainId,
  })),
);
const allowanceLabel = computed(() =>
  swapStore.fromToken.isNative
    ? "No approval needed"
    : `${formatUnits(swapStore.allowance, swapStore.fromToken.decimals, 4)} ${swapStore.fromToken.symbol}`,
);
const walletOnRouteChain = computed(
  () =>
    swapStore.walletChainId !== null &&
    swapStore.walletRouteChainIds.includes(swapStore.walletChainId),
);
const walletRouteStatus = computed(() => {
  if (!swapStore.walletConnected) {
    return "Connect a wallet first.";
  }

  if (swapStore.walletChainId === null) {
    return "Waiting for the wallet network.";
  }

  if (swapStore.walletChainId === swapStore.selectedChainId) {
    return `Wallet ready on ${walletChainLabel.value}.`;
  }

  if (walletOnRouteChain.value) {
    return `Wallet is on ${walletChainLabel.value}. You can use it as the send-from chain.`;
  }

  if (swapStore.walletChainSupported) {
    return `Wallet is on ${walletChainLabel.value}. Choose the bridge chain you want to send from.`;
  }

  return `Wallet is on ${walletChainLabel.value}, which is not part of this bridge route yet.`;
});
const routeNetworkButtonLabel = computed(() =>
  swapStore.walletNetworkAction === "adding-route-chains"
    ? "Adding chains"
    : "Add chains to wallet",
);
const networkPickerButtonLabel = computed(() =>
  swapStore.walletChainSupported ? "Manage chains" : "Choose wallet chain",
);
const hasPendingAction = computed(
  () =>
    swapStore.walletNetworkActionPending ||
    swapStore.status === "approving" ||
    swapStore.status === "swapping" ||
    swapStore.status === "switching-chain" ||
    swapStore.status === "connecting",
);
const pendingElapsedSeconds = computed(() =>
  pendingStartedAt.value === null ? 0 : nowSeconds.value - pendingStartedAt.value,
);
const pendingStatusDetails = computed(() => {
  if (swapStore.walletNetworkAction === "adding-chain") {
    return {
      title: "Adding chain to wallet",
      detail: "Accept the wallet prompt to add this chain before continuing.",
    };
  }

  if (swapStore.walletNetworkAction === "adding-route-chains") {
    return {
      title: "Adding bridge chains",
      detail: "The wallet may ask for more than one confirmation while it adds the supported chains.",
    };
  }

  if (swapStore.status === "connecting") {
    return {
      title: "Waiting for wallet connection",
      detail: "Check the wallet popup and approve the connection request.",
    };
  }

  if (swapStore.status === "switching-chain") {
    return {
      title: "Switching wallet network",
      detail: "The app is moving the wallet to the correct chain for this action.",
    };
  }

  if (swapStore.status === "approving") {
    return {
      title: "Approval transaction pending",
      detail: "The wallet accepted the approval. The app is waiting for it to confirm on-chain.",
    };
  }

  if (swapStore.status === "swapping") {
    return {
      title: "Transfer transaction pending",
      detail: "Your transfer has been submitted. Keep this tab open while the chain confirms it.",
    };
  }

  return null;
});

const statusTone = computed(() => {
  if (swapStore.status === "error") return "text-rose-200";
  if (swapStore.status === "success") return "text-emerald-200";
  if (
    swapStore.status === "approving" ||
    swapStore.status === "swapping" ||
    swapStore.status === "switching-chain" ||
    swapStore.status === "connecting"
  ) {
    return "text-amber-100";
  }

  return "text-white/60";
});

const buttonLabel = computed(() => {
  if (!swapStore.walletConnected) {
    return "Connect wallet";
  }

  switch (swapStore.status) {
    case "approval-required":
      return "Approve token";
    case "approving":
      return "Approving";
    case "connecting":
      return "Connecting";
    case "switching-chain":
      return "Switching chain";
    case "swapping":
      return "Sending money";
    case "ready":
      return "Send money";
    case "quoting":
      return "Preparing";
    default:
      return "Refresh";
  }
});

const buttonDisabled = computed(() => {
  if (!swapStore.walletConnected) {
    return swapStore.availableWallets.length === 0;
  }

  return hasPendingAction.value;
});

async function onAddRouteNetworks(): Promise<void> {
  await swapStore.addRouteChainsToWallet();
}

async function onAddWalletChain(chainId: number): Promise<void> {
  await swapStore.addChainToWallet(chainId);
}

async function onSelectSourceChain(chainId: number): Promise<void> {
  try {
    await swapStore.selectRouteSourceChain(chainId);
  } catch {
    // The store already surfaces wallet-switch failures through statusMessage.
  }
}

async function onActivateRouteChain(chainId: number): Promise<void> {
  await onSelectSourceChain(chainId);
  showNetworkPicker.value = false;
}

async function onSwapDirection(): Promise<void> {
  await onSelectSourceChain(swapStore.destinationChainId);
}

async function onPrimaryAction(): Promise<void> {
  if (!swapStore.walletConnected) {
    await swapStore.connectWallet();
    return;
  }

  if (swapStore.status === "approval-required") {
    await swapStore.approve();
    return;
  }

  if (swapStore.status === "ready" || swapStore.status === "success") {
    await swapStore.executeSwap();
    return;
  }

  await swapStore.refreshQuote();
}

watch(
  () =>
    [
      swapStore.walletConnected,
      swapStore.walletChainId,
      swapStore.walletChainSupported,
      swapStore.selectedChainId,
    ] as const,
  ([walletConnected, walletChainId, walletChainSupported, selectedChainId]) => {
    if (!walletConnected) {
      showNetworkPicker.value = false;
      return;
    }

    if (walletChainId === selectedChainId) {
      showNetworkPicker.value = false;
      return;
    }

    if (walletChainId !== null && !walletChainSupported) {
      showNetworkPicker.value = true;
    }
  },
  { immediate: true },
);

watch(
  () =>
    [
      swapStore.amountInText,
      swapStore.fromToken.address,
      swapStore.selectedChainId,
      swapStore.destinationChainId,
      swapStore.walletAddress,
    ] as const,
  async () => {
    await swapStore.refreshQuote();
  },
);

watch(
  hasPendingAction,
  (pending) => {
    if (pending && pendingStartedAt.value === null) {
      pendingStartedAt.value = Math.floor(Date.now() / 1000);
      return;
    }

    if (!pending) {
      pendingStartedAt.value = null;
    }
  },
  { immediate: true },
);

onMounted(() => {
  pendingTimer = window.setInterval(() => {
    nowSeconds.value = Math.floor(Date.now() / 1000);
  }, 1000);
});

onUnmounted(() => {
  if (pendingTimer !== null) {
    window.clearInterval(pendingTimer);
  }
});
</script>

<template>
  <section class="overflow-hidden rounded-[32px] border border-white/10 bg-white/[0.045] shadow-[0_28px_120px_rgba(0,0,0,0.35)] backdrop-blur-xl xl:sticky xl:top-6">
    <div class="border-b border-white/8 px-5 py-4 sm:px-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="text-xs uppercase tracking-[0.28em] text-white/45">Send Money</p>
          <h2 class="mt-2 font-display text-2xl font-semibold text-white">
            {{ sourceChainLabel }} to {{ destinationChainLabel }}
          </h2>
          <p class="mt-1 text-sm text-white/55">
            Pick where the money leaves from, how much to send, and where it arrives.
          </p>
        </div>
        <div class="rounded-full border border-white/10 bg-white/5 px-3 py-2 text-[11px] uppercase tracking-[0.22em] text-white/45">
          {{ walletLabel }}
        </div>
      </div>
    </div>

    <div class="space-y-4 px-5 py-5 sm:px-6">
      <div
        v-if="pendingStatusDetails"
        class="rounded-3xl border border-cyan-300/20 bg-cyan-300/10 p-4"
      >
        <div class="flex items-start gap-3">
          <div class="mt-1 h-4 w-4 animate-spin rounded-full border-2 border-cyan-100 border-t-transparent" />
          <div>
            <p class="text-sm font-semibold text-cyan-50">{{ pendingStatusDetails.title }}</p>
            <p class="mt-1 text-sm text-cyan-50/75">{{ pendingStatusDetails.detail }}</p>
            <p class="mt-3 text-xs text-cyan-50/65">
              Waiting {{ formatDuration(Math.max(pendingElapsedSeconds, 1)) }}
            </p>
            <p v-if="pendingElapsedSeconds >= 20" class="mt-2 text-xs text-cyan-50/65">
              This can take a while. Check the wallet popup if it is still open, and keep this page open until the status changes.
            </p>
          </div>
        </div>
      </div>

      <div class="rounded-3xl border border-white/8 bg-black/25 p-4">
        <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Step 1</p>
        <div class="mt-3 grid gap-4 sm:grid-cols-2">
          <div>
            <label class="mb-2 block text-sm font-semibold text-white">Send from</label>
            <select
              class="w-full rounded-2xl border border-white/10 bg-white/5 px-3 py-3 text-sm text-white outline-none transition focus:border-cyan-300/40"
              :value="swapStore.selectedChainId"
              @change="onSelectSourceChain(Number(($event.target as HTMLSelectElement).value))"
            >
              <option
                v-for="chain in SUPPORTED_CHAINS"
                :key="chain.id"
                :value="chain.id"
                class="bg-slate-950 text-white"
              >
                {{ chain.name }}
              </option>
            </select>
          </div>

          <div>
            <label class="mb-2 block text-sm font-semibold text-white">Receive on</label>
            <select
              class="w-full rounded-2xl border border-white/10 bg-white/5 px-3 py-3 text-sm text-white outline-none transition focus:border-cyan-300/40"
              :value="swapStore.destinationChainId"
              @change="swapStore.setDestinationChain(Number(($event.target as HTMLSelectElement).value))"
            >
              <option
                v-for="chain in SUPPORTED_CHAINS.filter((entry) => entry.id !== swapStore.selectedChainId)"
                :key="chain.id"
                :value="chain.id"
                class="bg-slate-950 text-white"
              >
                {{ chain.name }}
              </option>
            </select>
          </div>
        </div>

        <button
          type="button"
          class="mt-4 rounded-2xl border border-white/10 bg-white/5 px-4 py-2 text-sm font-semibold text-white transition hover:border-cyan-300/35 hover:text-cyan-50"
          @click="onSwapDirection"
        >
          Swap direction
        </button>
      </div>

      <div class="rounded-3xl border border-white/8 bg-black/25 p-4">
        <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Wallet setup</p>
            <p class="mt-2 text-sm font-semibold text-white">{{ walletRouteStatus }}</p>
            <p class="mt-1 text-xs text-white/45">
              If the wallet is on the wrong chain, use the buttons here and the app will guide the switch.
            </p>
          </div>

          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              class="rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm font-semibold text-white transition hover:border-cyan-300/35 hover:text-cyan-50 disabled:cursor-not-allowed disabled:opacity-40"
              :disabled="!swapStore.walletConnected || swapStore.walletNetworkActionPending"
              @click="showNetworkPicker = true"
            >
              {{ networkPickerButtonLabel }}
            </button>

            <button
              type="button"
              class="rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm font-semibold text-white transition hover:border-cyan-300/35 hover:text-cyan-50 disabled:cursor-not-allowed disabled:opacity-40"
              :disabled="!swapStore.walletConnected || swapStore.walletNetworkActionPending"
              @click="onAddRouteNetworks"
            >
              {{ routeNetworkButtonLabel }}
            </button>
          </div>
        </div>
      </div>

      <div class="rounded-3xl border border-white/8 bg-black/25 p-4">
        <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Step 2</p>
        <div class="mt-3 grid gap-4 lg:grid-cols-[minmax(0,1fr)_220px]">
          <div>
            <label class="mb-2 block text-sm font-semibold text-white">Amount to send</label>
            <div class="rounded-3xl border border-white/8 bg-white/[0.03] p-4">
              <div class="mb-3 flex items-center justify-between text-xs text-white/40">
                <span>Available {{ swapStore.formattedFromBalance }}</span>
                <span>{{ sourceChainLabel }}</span>
              </div>
              <div class="flex items-center gap-3">
                <input
                  class="w-full bg-transparent text-4xl font-display font-semibold text-white outline-none placeholder:text-white/25"
                  type="text"
                  inputmode="decimal"
                  :value="swapStore.amountInText"
                  @input="swapStore.setAmount(($event.target as HTMLInputElement).value)"
                />
                <select
                  class="rounded-2xl border border-white/10 bg-white/5 px-3 py-3 text-sm font-semibold text-white outline-none"
                  :value="swapStore.fromToken.address"
                  @change="swapStore.setSourceToken(($event.target as HTMLSelectElement).value as `0x${string}`)"
                >
                  <option
                    v-for="token in sourceTokens"
                    :key="token.address"
                    :value="token.address"
                    class="bg-slate-950 text-white"
                  >
                    {{ token.symbol }}
                  </option>
                </select>
              </div>
            </div>
          </div>

          <div>
            <label class="mb-2 block text-sm font-semibold text-white">Estimated arrival</label>
            <div class="rounded-3xl border border-white/8 bg-white/[0.03] p-4">
              <div class="mb-3 flex items-center justify-between text-xs text-white/40">
                <span>Current balance {{ swapStore.formattedToBalance }}</span>
                <span>{{ destinationChainLabel }}</span>
              </div>
              <p class="text-3xl font-display font-semibold text-white">
                {{ swapStore.formattedQuote }}
              </p>
              <p class="mt-1 text-sm text-white/50">{{ destinationToken?.symbol ?? 'Unsupported' }}</p>
            </div>
          </div>
        </div>
      </div>

      <div class="rounded-3xl border border-white/8 bg-black/25 p-4">
        <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Step 3</p>
        <div class="mt-3 space-y-3 text-sm text-white/55">
          <div class="flex items-center justify-between rounded-2xl border border-white/8 bg-white/[0.03] px-4 py-3">
            <span>Route</span>
            <span class="font-semibold text-white">{{ swapStore.quote?.routeLabel ?? '-' }}</span>
          </div>
          <div class="flex items-center justify-between rounded-2xl border border-white/8 bg-white/[0.03] px-4 py-3">
            <span>Destination asset</span>
            <span class="font-semibold text-white">{{ destinationToken?.name ?? 'Unavailable' }}</span>
          </div>
          <div class="flex items-center justify-between rounded-2xl border border-white/8 bg-white/[0.03] px-4 py-3">
            <span>Approval</span>
            <span class="font-semibold text-white">{{ allowanceLabel }}</span>
          </div>
        </div>
      </div>

      <div class="rounded-3xl border border-white/8 bg-black/25 p-4">
        <p class="text-sm" :class="statusTone">{{ swapStore.statusMessage }}</p>
        <p v-if="swapStore.lastTxHash" class="mt-2 font-mono text-xs text-white/35">
          {{ shortenAddress(swapStore.lastTxHash, 6) }}
        </p>
      </div>

      <button
        type="button"
        class="w-full rounded-3xl bg-gradient-to-r from-emerald-400 via-cyan-400 to-sky-400 px-5 py-4 text-base font-semibold text-slate-950 transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-40"
        :disabled="buttonDisabled"
        @click="onPrimaryAction"
      >
        <span class="inline-flex items-center gap-2">
          <span
            v-if="hasPendingAction"
            class="h-4 w-4 animate-spin rounded-full border-2 border-slate-900/70 border-t-transparent"
          />
          {{ buttonLabel }}
        </span>
      </button>
    </div>

    <div
      v-if="showNetworkPicker"
      class="fixed inset-0 z-20 flex items-end bg-slate-950/80 p-3 backdrop-blur-sm sm:items-center sm:justify-center sm:p-6"
      @click.self="showNetworkPicker = false"
    >
      <div
        class="w-full max-w-2xl rounded-[28px] border border-white/10 bg-[#09151b] p-5 shadow-[0_30px_120px_rgba(0,0,0,0.45)] sm:p-6"
        role="dialog"
        aria-modal="true"
        aria-label="Bridge chain picker"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="text-xs uppercase tracking-[0.28em] text-white/40">Choose Chain</p>
            <h3 class="mt-2 font-display text-2xl font-semibold text-white">Pick the wallet chain to send from</h3>
            <p class="mt-2 text-sm text-white/55">
              This updates the route and switches the wallet if needed. You can also add each chain to the wallet first.
            </p>
          </div>

          <button
            type="button"
            class="rounded-2xl border border-white/10 bg-white/5 px-3 py-2 text-sm font-semibold text-white transition hover:border-cyan-300/35 hover:text-cyan-50"
            @click="showNetworkPicker = false"
          >
            Close
          </button>
        </div>

        <div class="mt-5 grid gap-3 sm:grid-cols-2">
          <article
            v-for="network in routeChainActions"
            :key="`picker-${network.chainId}`"
            class="rounded-3xl border border-white/10 bg-black/25 p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="text-sm font-semibold text-white">{{ network.label }}</p>
                <p class="mt-1 text-xs text-white/45">
                  {{
                    network.isSelectedSource
                      ? 'Current send-from chain.'
                      : `Use ${network.label} for the next transfer.`
                  }}
                </p>
              </div>

              <span
                class="rounded-full border px-2.5 py-1 text-[11px] uppercase tracking-[0.18em]"
                :class="network.isWalletActive
                  ? 'border-cyan-300/25 bg-cyan-300/10 text-cyan-50'
                  : 'border-white/10 bg-white/5 text-white/60'"
              >
                {{ network.isWalletActive ? 'Wallet active' : 'Available' }}
              </span>
            </div>

            <div class="mt-4 flex flex-wrap gap-2">
              <button
                type="button"
                class="rounded-2xl border border-white/10 bg-black/20 px-3 py-2 text-sm font-semibold text-white transition hover:border-cyan-300/35 hover:text-cyan-50 disabled:cursor-not-allowed disabled:opacity-40"
                :disabled="!swapStore.walletConnected || swapStore.walletNetworkActionPending || (network.isSelectedSource && network.isWalletActive)"
                @click="onActivateRouteChain(network.chainId)"
              >
                {{
                  network.isSelectedSource && network.isWalletActive
                    ? 'Ready'
                    : network.isSelectedSource
                      ? 'Switch wallet here'
                      : network.isWalletActive
                        ? 'Use this wallet chain'
                        : 'Send from here'
                }}
              </button>

              <button
                type="button"
                class="rounded-2xl border border-white/10 bg-white/5 px-3 py-2 text-sm font-semibold text-white transition hover:border-cyan-300/35 hover:text-cyan-50 disabled:cursor-not-allowed disabled:opacity-40"
                :disabled="!swapStore.walletConnected || swapStore.walletNetworkActionPending"
                @click="onAddWalletChain(network.chainId)"
              >
                {{
                  network.isPending && swapStore.walletNetworkAction === 'adding-chain'
                    ? 'Adding'
                    : 'Add to wallet'
                }}
              </button>
            </div>
          </article>
        </div>
      </div>
    </div>
  </section>
</template>
