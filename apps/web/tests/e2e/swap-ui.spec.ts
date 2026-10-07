import { test, expect } from "@playwright/test";

test("a disconnected user can inspect balances and activity without sending funds", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Move money between Ethereum and Base." })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Ethereum to Base", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Connect wallet", exact: true }).last()).toBeDisabled();

  await page.getByRole("button", { name: "Balances See what is available now" }).click();
  await expect(page.getByRole("heading", { name: "Your money by chain" })).toBeVisible();
  await expect(page.getByText("Wallet connection required", { exact: true })).toBeVisible();

  await page.getByRole("button", { name: "Activity Track progress and receive funds" }).click();
  await expect(page.getByRole("heading", { name: "Transfer progress" })).toBeVisible();
  await expect(page.getByText("Connect a wallet to load transfers and see when funds are ready to receive.", { exact: true })).toBeVisible();
});
