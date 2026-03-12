<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import OperationsOverviewPanel from "@/components/OperationsOverviewPanel.vue";
import SwapCard from "@/components/SwapCard.vue";
import TransferHistoryPanel from "@/components/TransferHistoryPanel.vue";
import WalletPanel from "@/components/WalletPanel.vue";
import { useSwapStore } from "@/stores/swap";
import { chainLabel } from "@/config/networks";
import { shortenAddress } from "@/utils/format";

type AppTabId = "bridge" | "balances" | "activity" | "system";

const swapStore = useSwapStore();
const activeTab = ref<AppTabId>("bridge");

const appTabs = [
  {
    id: "bridge",
    label: "Send Money",
    description: "Move funds between chains",
  },
  {
    id: "balances",
    label: "Balances",
    description: "See what is available now",
  },
  {
    id: "activity",
    label: "Activity",
    description: "Track progress and receive funds",
  },
  {
    id: "system",
    label: "Bridge Health",
    description: "Validator and proof status",
  },
] as const satisfies ReadonlyArray<{
  id: AppTabId;
  label: string;
  description: string;
}>;

const walletLabel = computed(() =>
  swapStore.walletAddress ? shortenAddress(swapStore.walletAddress, 5) : "Not connected",
);
const walletChainLabel = computed(() =>
  swapStore.walletChainId ? chainLabel(swapStore.walletChainId) : "No active network",
);
const routeLabel = computed(
  () => `${chainLabel(swapStore.selectedChainId)} to ${chainLabel(swapStore.destinationChainId)}`,
);
const activeWalletName = computed(() => swapStore.connectedWalletName ?? "No wallet");
const activeTabDetails = computed(
  () => appTabs.find((tab) => tab.id === activeTab.value) ?? appTabs[0],
);

onMounted(async () => {
  await swapStore.initialize();
});
</script>

<template>
  <main class="relative min-h-screen overflow-hidden bg-[#071015] text-white">
    <div class="pointer-events-none absolute inset-0 overflow-hidden">
      <div class="absolute left-[-6rem] top-[-4rem] h-72 w-72 rounded-full bg-emerald-400/16 blur-3xl" />
      <div class="absolute right-[-4rem] top-20 h-80 w-80 rounded-full bg-cyan-400/12 blur-3xl" />
      <div class="absolute bottom-[-8rem] left-1/3 h-96 w-96 rounded-full bg-amber-300/8 blur-3xl" />
      <div class="absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.07),transparent_28%),linear-gradient(180deg,rgba(255,255,255,0.03),transparent_30%),linear-gradient(90deg,rgba(255,255,255,0.03)_1px,transparent_1px)] bg-[length:100%_100%,100%_100%,36px_36px] opacity-30" />
    </div>

    <div class="relative mx-auto flex min-h-screen w-full max-w-7xl flex-col px-4 py-5 sm:px-6 lg:px-8">
      <header class="rounded-[32px] border border-white/10 bg-white/[0.045] px-5 py-5 shadow-[0_20px_100px_rgba(0,0,0,0.3)] backdrop-blur-xl sm:px-6">
        <div class="flex flex-col gap-6">
          <div class="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
            <div class="max-w-3xl">
              <p class="text-xs uppercase tracking-[0.32em] text-white/40">Bridge</p>
              <h1 class="mt-3 font-display text-4xl font-semibold tracking-tight text-white sm:text-5xl">
                Move money between Ethereum and Base.
              </h1>
              <p class="mt-3 text-sm leading-6 text-white/55 sm:text-base">
                Use the tabs to send money, check balances, or follow transfer progress without
                digging through one long page.
              </p>
            </div>

            <div class="flex flex-col gap-3 xl:items-end">
              <div class="flex flex-col gap-2 rounded-3xl border border-white/10 bg-black/25 p-3 sm:flex-row sm:items-center">
                <select
                  class="min-w-[220px] rounded-2xl border border-white/10 bg-white/5 px-3 py-3 text-sm text-white outline-none transition focus:border-cyan-300/40"
                  :value="swapStore.selectedWalletUuid ?? ''"
                  @change="swapStore.setWallet(($event.target as HTMLSelectElement).value)"
                >
                  <option value="" disabled class="bg-slate-950 text-white">
                    Select wallet
                  </option>
                  <option
                    v-for="wallet in swapStore.availableWallets"
                    :key="wallet.info.uuid"
                    :value="wallet.info.uuid"
                    class="bg-slate-950 text-white"
                  >
                    {{ wallet.info.name }}
                  </option>
                </select>

                <button
                  type="button"
                  class="rounded-2xl border border-cyan-300/25 bg-cyan-300/10 px-4 py-3 text-sm font-semibold text-cyan-50 transition hover:border-cyan-200/40 hover:bg-cyan-300/15"
                  @click="swapStore.walletConnected ? swapStore.disconnectWallet() : swapStore.connectWallet()"
                >
                  {{ swapStore.walletConnected ? 'Disconnect' : 'Connect wallet' }}
                </button>
              </div>
            </div>
          </div>

          <div class="grid gap-3 md:grid-cols-3">
            <div class="rounded-2xl border border-white/8 bg-black/20 px-4 py-3">
              <p class="text-[11px] uppercase tracking-[0.2em] text-white/35">Wallet</p>
              <p class="mt-2 font-mono text-sm text-white/80">{{ walletLabel }}</p>
              <p class="mt-1 text-xs text-white/45">{{ activeWalletName }}</p>
            </div>
            <div class="rounded-2xl border border-white/8 bg-black/20 px-4 py-3">
              <p class="text-[11px] uppercase tracking-[0.2em] text-white/35">Wallet network</p>
              <p class="mt-2 text-sm font-semibold text-white">{{ walletChainLabel }}</p>
              <p class="mt-1 text-xs text-white/45">Current route: {{ routeLabel }}</p>
            </div>
            <div class="rounded-2xl border border-white/8 bg-black/20 px-4 py-3">
              <p class="text-[11px] uppercase tracking-[0.2em] text-white/35">Next step</p>
              <p class="mt-2 text-sm font-semibold text-white/80">
                {{ swapStore.statusMessage || activeTabDetails.description }}
              </p>
            </div>
          </div>
        </div>
      </header>

      <nav class="mt-6 rounded-[28px] border border-white/10 bg-black/20 p-2 backdrop-blur-xl">
        <div class="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
          <button
            v-for="tab in appTabs"
            :key="tab.id"
            type="button"
            class="rounded-[22px] border px-4 py-3 text-left transition"
            :class="activeTab === tab.id
              ? 'border-cyan-300/40 bg-cyan-300/10 text-cyan-50'
              : 'border-white/8 bg-white/[0.03] text-white/70 hover:border-white/15 hover:text-white'"
            @click="activeTab = tab.id"
          >
            <p class="text-sm font-semibold">{{ tab.label }}</p>
            <p class="mt-1 text-xs text-white/45">{{ tab.description }}</p>
          </button>
        </div>
      </nav>

      <section v-if="activeTab === 'bridge'" class="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1fr)_320px]">
        <SwapCard />

        <aside class="space-y-4">
          <section class="rounded-[28px] border border-white/10 bg-white/[0.045] p-5 shadow-[0_24px_90px_rgba(0,0,0,0.28)] backdrop-blur-xl">
            <p class="text-xs uppercase tracking-[0.28em] text-white/40">How It Works</p>
            <div class="mt-4 space-y-3 text-sm text-white/65">
              <div class="rounded-3xl border border-white/8 bg-black/20 p-4">
                <p class="font-semibold text-white">1. Pick where the money leaves from</p>
                <p class="mt-1">Choose the source chain, the destination chain, and the amount.</p>
              </div>
              <div class="rounded-3xl border border-white/8 bg-black/20 p-4">
                <p class="font-semibold text-white">2. Confirm the deposit</p>
                <p class="mt-1">The wallet switches to the right chain before you send anything.</p>
              </div>
              <div class="rounded-3xl border border-white/8 bg-black/20 p-4">
                <p class="font-semibold text-white">3. Receive on the other chain</p>
                <p class="mt-1">The Activity tab will tell you when the money is ready to receive.</p>
              </div>
            </div>
          </section>

          <section class="rounded-[28px] border border-white/10 bg-white/[0.045] p-5 shadow-[0_24px_90px_rgba(0,0,0,0.28)] backdrop-blur-xl">
            <p class="text-xs uppercase tracking-[0.28em] text-white/40">Current Route</p>
            <p class="mt-3 font-display text-2xl font-semibold text-white">{{ routeLabel }}</p>
            <p class="mt-2 text-sm text-white/55">
              Keep this tab focused on sending money. Use Balances to check holdings and Activity
              to finish transfers that are ready.
            </p>
          </section>
        </aside>
      </section>

      <section v-else-if="activeTab === 'balances'" class="mt-6">
        <WalletPanel />
      </section>

      <section v-else-if="activeTab === 'activity'" class="mt-6">
        <TransferHistoryPanel />
      </section>

      <section v-else class="mt-6 pb-6">
        <OperationsOverviewPanel />
      </section>
    </div>
  </main>
</template>
