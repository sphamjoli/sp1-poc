import { test, expect } from "@playwright/test";

test("terminal screen shows balances and transfer activity", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByText("Bridge Exchange")).toBeVisible();
  await expect(page.getByText("Cross-chain transfers with clear wallet state and verifiable progress.")).toBeVisible();
  await expect(page.getByText("Current Chain Balances")).toBeVisible();
  await expect(page.getByText("Swap Ticket")).toBeVisible();
  await expect(page.getByText("Wallet History")).toBeVisible();
  await expect(page.getByRole("button", { name: /Execute Swap|Approve Token|Refresh Quote/i })).toBeVisible();
});
