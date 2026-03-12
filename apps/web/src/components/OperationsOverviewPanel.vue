<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import { fetchOperationsDashboard, topUpRewardReserve } from "@/services/operations";
import { formatUnits, parseUnits } from "@/utils/amount";
import { formatTimestamp, shortenAddress } from "@/utils/format";
import type { OperationsDashboardData } from "@/types/operations";

const dashboard = ref<OperationsDashboardData | null>(null);
const loading = ref(false);
const errorMessage = ref("");
const refreshedAt = ref<number | null>(null);
const rewardTopUpAmount = ref("10");
const rewardTopUpPending = ref(false);
const rewardTopUpError = ref("");
const rewardTopUpSuccess = ref("");
let refreshTimer: number | null = null;

const validatorCount = computed(() => dashboard.value?.runtime.validators.length ?? 0);
const activeValidatorCount = computed(() => dashboard.value?.runtime.activeValidatorCount ?? 0);
const recentCertificates = computed(() => dashboard.value?.runtime.recentCertificates ?? []);
const validatorProcesses = computed(() => dashboard.value?.runtime.validatorProcesses ?? []);
const hasProofError = computed(() => Boolean(dashboard.value?.runtime.sp1?.lastError));

function formatEtherAmount(value: bigint | null, precision = 4): string {
  if (value === null) {
    return "-";
  }

  return `${formatUnits(value, 18, precision)} ETH`;
}

function formatRewardTokenAmount(value: bigint | null, precision = 4): string {
  if (value === null || !dashboard.value) {
    return "-";
  }

  return `${formatUnits(value, dashboard.value.runtime.rewardTokenDecimals, precision)} ${dashboard.value.runtime.rewardTokenSymbol}`;
}

async function refreshOperations(): Promise<void> {
  loading.value = true;
  errorMessage.value = "";

  try {
    dashboard.value = await fetchOperationsDashboard();
    refreshedAt.value = Math.floor(Date.now() / 1000);
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : String(error);
  } finally {
    loading.value = false;
  }
}

async function submitRewardTopUp(): Promise<void> {
  if (!dashboard.value) {
    return;
  }

  rewardTopUpPending.value = true;
  rewardTopUpError.value = "";
  rewardTopUpSuccess.value = "";

  try {
    const amountWei = parseUnits(
      rewardTopUpAmount.value,
      dashboard.value.runtime.rewardTokenDecimals,
    );
    if (amountWei <= 0n) {
      throw new Error("Enter an amount greater than zero");
    }

    const result = await topUpRewardReserve(amountWei.toString());
    rewardTopUpSuccess.value =
      `Reserve funded with ${formatUnits(amountWei, dashboard.value.runtime.rewardTokenDecimals, 4)} ` +
      `${dashboard.value.runtime.rewardTokenSymbol}. Top-up tx ${shortenAddress(result.topUpTransactionHash, 6)}.`;
    await refreshOperations();
  } catch (error) {
    rewardTopUpError.value = error instanceof Error ? error.message : String(error);
  } finally {
    rewardTopUpPending.value = false;
  }
}

onMounted(async () => {
  await refreshOperations();
  refreshTimer = window.setInterval(async () => {
    await refreshOperations();
  }, 5000);
});

onUnmounted(() => {
  if (refreshTimer !== null) {
    window.clearInterval(refreshTimer);
  }
});
</script>

<template>
  <section class="overflow-hidden rounded-[32px] border border-white/10 bg-white/[0.045] shadow-[0_30px_110px_rgba(0,0,0,0.3)] backdrop-blur-xl">
    <div class="border-b border-white/8 px-5 py-4 sm:px-6">
      <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p class="text-xs uppercase tracking-[0.28em] text-white/45">Operations</p>
          <h2 class="mt-2 font-display text-2xl font-semibold text-white">Validator, Proof, and Chain State</h2>
          <p class="mt-1 text-sm text-white/55">Live runtime and indexed bridge metrics across validators, certificates, rewards, proofs, and fees.</p>
        </div>

        <div class="flex items-center gap-3 text-xs text-white/40">
          <span v-if="refreshedAt">Updated {{ formatTimestamp(refreshedAt) }}</span>
          <button
            type="button"
            class="rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-white/65 transition hover:border-cyan-300/30 hover:text-white"
            @click="refreshOperations"
          >
            Refresh
          </button>
        </div>
      </div>
    </div>

    <div class="px-5 py-5 sm:px-6">
      <div v-if="loading && !dashboard" class="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <div v-for="index in 4" :key="index" class="h-28 animate-pulse rounded-3xl border border-white/8 bg-white/5" />
      </div>

      <div v-else-if="errorMessage" class="rounded-3xl border border-rose-500/20 bg-rose-500/10 px-4 py-4 text-sm text-rose-100">
        {{ errorMessage }}
      </div>

      <div v-else-if="dashboard" class="space-y-5">
        <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          <article class="rounded-3xl border border-white/8 bg-black/25 p-4">
            <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Current epoch</p>
            <p class="mt-2 font-display text-3xl font-semibold text-white">{{ dashboard.runtime.currentEpoch }}</p>
            <p class="mt-1 text-xs text-white/45">{{ dashboard.runtime.epochDurationSeconds }}s window</p>
          </article>

          <article class="rounded-3xl border border-white/8 bg-black/25 p-4">
            <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Active validators</p>
            <p class="mt-2 font-display text-3xl font-semibold text-white">{{ activeValidatorCount }}</p>
            <p class="mt-1 text-xs text-white/45">{{ validatorCount }} tracked in catalog</p>
          </article>

          <article class="rounded-3xl border border-white/8 bg-black/25 p-4">
            <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Total base stake</p>
            <p class="mt-2 font-display text-3xl font-semibold text-white">{{ formatEtherAmount(dashboard.runtime.totalBaseStakeAmount) }}</p>
            <p class="mt-1 text-xs text-white/45">Pending rewards {{ formatRewardTokenAmount(dashboard.runtime.totalPendingRewards, 5) }}</p>
          </article>

          <article class="rounded-3xl border border-white/8 bg-black/25 p-4">
            <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Certificates issued</p>
            <p class="mt-2 font-display text-3xl font-semibold text-white">{{ dashboard.runtime.certificateCount }}</p>
            <p class="mt-1 text-xs" :class="hasProofError ? 'text-amber-200' : 'text-white/45'">
              {{ hasProofError ? 'SP1 loop needs attention' : 'SP1 loop healthy' }}
            </p>
          </article>
        </div>

        <div class="grid gap-5 xl:grid-cols-[1.3fr_minmax(0,1fr)]">
          <section class="rounded-3xl border border-white/8 bg-black/25 p-4">
            <div class="flex items-center justify-between gap-3">
              <div>
                <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Chain throughput</p>
                <h3 class="mt-2 font-display text-xl font-semibold text-white">Bridge totals by chain</h3>
              </div>
              <div class="text-right text-xs text-white/40">
                <p>{{ dashboard.summary.totalDeposits }} deposits</p>
                <p>{{ dashboard.summary.totalClaims }} claims</p>
              </div>
            </div>

            <div class="mt-4 space-y-3">
              <article
                v-for="chain in dashboard.chains"
                :key="chain.id"
                class="rounded-3xl border border-white/8 bg-white/[0.03] p-4"
              >
                <div class="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
                  <div>
                    <p class="text-sm font-semibold text-white">{{ chain.name }}</p>
                    <p class="mt-1 text-xs text-white/45">Chain {{ chain.id }}</p>
                  </div>
                  <div class="grid grid-cols-2 gap-4 text-sm text-white/55 sm:grid-cols-4">
                    <div>
                      <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Deposits</p>
                      <p class="mt-1 font-semibold text-white">{{ chain.totalDeposits }}</p>
                    </div>
                    <div>
                      <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Claims</p>
                      <p class="mt-1 font-semibold text-white">{{ chain.totalClaims }}</p>
                    </div>
                    <div>
                      <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Volume in</p>
                      <p class="mt-1 font-semibold text-white">{{ formatEtherAmount(chain.totalVolumeDeposited) }}</p>
                    </div>
                    <div>
                      <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Volume out</p>
                      <p class="mt-1 font-semibold text-white">{{ formatEtherAmount(chain.totalVolumeClaimed) }}</p>
                    </div>
                  </div>
                </div>
              </article>
            </div>
          </section>

          <div class="space-y-5">
            <section class="rounded-3xl border border-white/8 bg-black/25 p-4">
              <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Proof runtime</p>
              <h3 class="mt-2 font-display text-xl font-semibold text-white">SP1 and agent health</h3>
              <div class="mt-4 space-y-3 text-sm text-white/55">
                <div class="rounded-3xl border border-white/8 bg-white/[0.03] p-4">
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Chain manager</p>
                  <p class="mt-2 font-semibold text-white">{{ dashboard.runtime.chainManager?.status ?? 'Unknown' }}</p>
                  <p class="mt-1 text-xs text-white/45">{{ dashboard.runtime.chainManager?.bind ?? 'No heartbeat' }}</p>
                </div>
                <div class="rounded-3xl border border-white/8 bg-white/[0.03] p-4">
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">SP1 loop</p>
                  <p class="mt-2 font-semibold text-white">{{ dashboard.runtime.sp1?.status ?? 'Unknown' }}</p>
                  <p v-if="dashboard.runtime.sp1?.lastRunAt" class="mt-1 text-xs text-white/45">Last run {{ formatTimestamp(dashboard.runtime.sp1.lastRunAt) }}</p>
                  <p v-if="dashboard.runtime.sp1?.lastError" class="mt-2 text-xs text-amber-200">{{ dashboard.runtime.sp1.lastError }}</p>
                </div>
                <div class="rounded-3xl border border-white/8 bg-white/[0.03] p-4">
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Average fees</p>
                  <div class="mt-3 grid gap-2 text-xs text-white/55">
                    <div class="flex items-center justify-between">
                      <span>Deposit</span>
                      <span class="font-semibold text-white">{{ formatEtherAmount(dashboard.fees.averageDepositFeeWei, 6) }}</span>
                    </div>
                    <div class="flex items-center justify-between">
                      <span>Claim</span>
                      <span class="font-semibold text-white">{{ formatEtherAmount(dashboard.fees.averageClaimFeeWei, 6) }}</span>
                    </div>
                    <div class="flex items-center justify-between">
                      <span>Attestation</span>
                      <span class="font-semibold text-white">{{ formatEtherAmount(dashboard.fees.averageAttestationFeeWei, 6) }}</span>
                    </div>
                  </div>
                </div>
              </div>
            </section>

            <section class="rounded-3xl border border-white/8 bg-black/25 p-4">
              <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Reward reserve</p>
              <h3 class="mt-2 font-display text-xl font-semibold text-white">Top up validator claims</h3>
              <p class="mt-1 text-sm text-white/55">
                Funds the stake manager reserve used when validators claim rewards. This does not distribute rewards by itself.
              </p>

              <div class="mt-4 grid gap-3 sm:grid-cols-3">
                <div class="rounded-3xl border border-white/8 bg-white/[0.03] p-4">
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Reserve now</p>
                  <p class="mt-2 font-semibold text-white">
                    {{ formatRewardTokenAmount(dashboard.runtime.rewardReserveBalance, 4) }}
                  </p>
                </div>
                <div class="rounded-3xl border border-white/8 bg-white/[0.03] p-4">
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Owner balance</p>
                  <p class="mt-2 font-semibold text-white">
                    {{ formatRewardTokenAmount(dashboard.runtime.ownerRewardTokenBalance, 4) }}
                  </p>
                </div>
                <div class="rounded-3xl border border-white/8 bg-white/[0.03] p-4">
                  <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Contracts</p>
                  <p class="mt-2 text-xs text-white/65">
                    {{ shortenAddress(dashboard.runtime.rewardTokenAddress, 5) }} token
                  </p>
                  <p class="mt-1 text-xs text-white/45">
                    {{ shortenAddress(dashboard.runtime.baseStakeManager, 5) }} stake manager
                  </p>
                </div>
              </div>

              <div class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end">
                <label class="flex-1">
                  <span class="text-[11px] uppercase tracking-[0.18em] text-white/35">Amount to add</span>
                  <input
                    v-model="rewardTopUpAmount"
                    type="text"
                    inputmode="decimal"
                    class="mt-2 w-full rounded-2xl border border-white/10 bg-white/5 px-3 py-3 text-sm text-white outline-none transition focus:border-cyan-300/40"
                    :placeholder="`10 ${dashboard.runtime.rewardTokenSymbol}`"
                  />
                </label>

                <button
                  type="button"
                  class="inline-flex min-h-[48px] items-center justify-center gap-2 rounded-2xl border border-cyan-300/25 bg-cyan-300/10 px-4 py-3 text-sm font-semibold text-cyan-50 transition hover:border-cyan-200/40 hover:bg-cyan-300/15 disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="rewardTopUpPending || loading"
                  @click="submitRewardTopUp"
                >
                  <span
                    v-if="rewardTopUpPending"
                    class="h-4 w-4 animate-spin rounded-full border-2 border-cyan-100 border-t-transparent"
                  />
                  {{ rewardTopUpPending ? "Funding reserve" : "Top up reserve" }}
                </button>
              </div>

              <div
                v-if="rewardTopUpError"
                class="mt-4 rounded-3xl border border-rose-500/20 bg-rose-500/10 px-4 py-4 text-sm text-rose-100"
              >
                {{ rewardTopUpError }}
              </div>

              <div
                v-else-if="rewardTopUpSuccess"
                class="mt-4 rounded-3xl border border-emerald-400/20 bg-emerald-400/10 px-4 py-4 text-sm text-emerald-100"
              >
                {{ rewardTopUpSuccess }}
              </div>
            </section>

            <section class="rounded-3xl border border-white/8 bg-black/25 p-4">
              <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Certificates</p>
              <h3 class="mt-2 font-display text-xl font-semibold text-white">Recent issuance</h3>
              <div class="mt-4 space-y-3">
                <article
                  v-for="certificate in recentCertificates.slice(0, 5)"
                  :key="`${certificate.validator}:${certificate.issuedAt}:${certificate.targetChainId}`"
                  class="rounded-3xl border border-white/8 bg-white/[0.03] p-4"
                >
                  <div class="flex items-start justify-between gap-3">
                    <div>
                      <p class="text-sm font-semibold text-white">{{ shortenAddress(certificate.validator, 5) }}</p>
                      <p class="mt-1 text-xs text-white/45">Target chain {{ certificate.targetChainId }}</p>
                    </div>
                    <span class="rounded-full border border-white/10 bg-white/5 px-2.5 py-1 text-[11px] uppercase tracking-[0.2em] text-white/45">
                      {{ formatTimestamp(certificate.issuedAt) }}
                    </span>
                  </div>
                </article>
                <div v-if="recentCertificates.length === 0" class="rounded-3xl border border-dashed border-white/12 bg-black/20 px-4 py-6 text-sm text-white/45">
                  No certificates issued yet in this session.
                </div>
              </div>
            </section>
          </div>
        </div>

        <div class="grid gap-5 xl:grid-cols-[1.4fr_minmax(0,1fr)]">
          <section class="rounded-3xl border border-white/8 bg-black/25 p-4">
            <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Validators</p>
            <h3 class="mt-2 font-display text-xl font-semibold text-white">Stake, rewards, and sync state</h3>
            <div class="mt-4 space-y-3">
              <article
                v-for="validator in dashboard.runtime.validators"
                :key="validator.wallet"
                class="rounded-3xl border border-white/8 bg-white/[0.03] p-4"
              >
                <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                  <div>
                    <div class="flex flex-wrap items-center gap-2">
                      <p class="text-sm font-semibold text-white">{{ validator.name }}</p>
                      <span
                        class="rounded-full px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.2em]"
                        :class="validator.baseStatus === 'Active' ? 'bg-emerald-400/15 text-emerald-200' : 'bg-amber-400/15 text-amber-100'"
                      >
                        {{ validator.baseStatus }}
                      </span>
                    </div>
                    <p class="mt-1 font-mono text-xs text-white/45">{{ shortenAddress(validator.wallet, 5) }}</p>
                  </div>

                  <div class="grid grid-cols-2 gap-4 text-sm text-white/55 sm:grid-cols-4">
                    <div>
                      <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Stake</p>
                      <p class="mt-1 font-semibold text-white">{{ formatEtherAmount(validator.baseStakeAmount) }}</p>
                    </div>
                    <div>
                      <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Rewards</p>
                      <p class="mt-1 font-semibold text-white">{{ formatRewardTokenAmount(validator.pendingRewards, 5) }}</p>
                    </div>
                    <div>
                      <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Attestations</p>
                      <p class="mt-1 font-semibold text-white">{{ validator.attestationCount }}</p>
                    </div>
                    <div>
                      <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Reward epoch</p>
                      <p class="mt-1 font-semibold text-white">{{ validator.lastRewardEpoch }}</p>
                    </div>
                  </div>
                </div>

                <div class="mt-4 flex flex-wrap gap-2">
                  <span
                    v-for="syncStatus in validator.synced"
                    :key="`${validator.wallet}:${syncStatus.chain_id}`"
                    class="rounded-full border px-2.5 py-1 text-[11px] uppercase tracking-[0.18em]"
                    :class="syncStatus.status === syncStatus.expected_status
                      ? 'border-emerald-400/20 bg-emerald-400/10 text-emerald-200'
                      : 'border-amber-400/20 bg-amber-400/10 text-amber-100'"
                  >
                    {{ syncStatus.chain_id }} · {{ syncStatus.status }}
                  </span>
                </div>
              </article>
            </div>
          </section>

          <section class="rounded-3xl border border-white/8 bg-black/25 p-4">
            <p class="text-[11px] uppercase tracking-[0.22em] text-white/38">Validator runtime</p>
            <h3 class="mt-2 font-display text-xl font-semibold text-white">Process state</h3>
            <div class="mt-4 space-y-3">
              <article
                v-for="processState in validatorProcesses"
                :key="processState.validator"
                class="rounded-3xl border border-white/8 bg-white/[0.03] p-4"
              >
                <div class="flex items-center justify-between gap-3">
                  <div>
                    <p class="text-sm font-semibold text-white">{{ processState.validator }}</p>
                    <p class="mt-1 text-xs text-white/45">
                      {{ processState.lastHeartbeatAt ? `Heartbeat ${formatTimestamp(processState.lastHeartbeatAt)}` : 'No heartbeat yet' }}
                    </p>
                  </div>
                  <span
                    class="rounded-full px-2.5 py-1 text-[11px] uppercase tracking-[0.18em]"
                    :class="processState.lastError ? 'bg-amber-400/15 text-amber-100' : 'bg-emerald-400/15 text-emerald-200'"
                  >
                    {{ processState.lastError ? 'Attention' : 'Healthy' }}
                  </span>
                </div>
                <div class="mt-3 grid grid-cols-3 gap-3 text-xs text-white/50">
                  <div>
                    <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Submitted</p>
                    <p class="mt-1 font-semibold text-white">{{ processState.submittedCount }}</p>
                  </div>
                  <div>
                    <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Pending</p>
                    <p class="mt-1 font-semibold text-white">{{ processState.pendingCount }}</p>
                  </div>
                  <div>
                    <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">Retrying</p>
                    <p class="mt-1 font-semibold text-white">{{ processState.retryingCount }}</p>
                  </div>
                </div>
                <p v-if="processState.lastError" class="mt-3 text-xs text-amber-200">{{ processState.lastError }}</p>
              </article>
            </div>
          </section>
        </div>
      </div>
    </div>
  </section>
</template>
