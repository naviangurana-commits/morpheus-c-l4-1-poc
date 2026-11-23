# Morpheus Bounty PoC — C-L4-1: BuildersV4 withdraw-lock trap

**Finding.** In BuildersV4 (Base), `withdraw()` reads `withdrawLockPeriodAfterDeposit`
live from the subnet config, and `editSubnet()` can rewrite it at any time with no
maximum and no freeze after deposits. A subnet admin — a permissionless user role,
anyone can create a subnet — can retroactively extend the lock on stakes already
deposited (up to ~100 years, or `type(uint128).max`, which makes `withdraw()` revert
unconditionally on overflow), trapping every staker's principal in that subnet
indefinitely. Builders V1–V3 froze pool parameters once staking could exist; V4
dropped both guards.

**Target.** BuildersV4 proxy `0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9` (Base),
implementation `0x18faef315b40a6d9cf49628f1133b1aa507513b0` (Sourcify exact match).

## Run it

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`).
One command from the repo root:

```
forge test
```

The fork is pinned in-code (`test/ForkLane4.t.sol`, `setUp()`):
Base mainnet block **61,369,794** via the public endpoint
`https://base-rpc.publicnode.com`. No other setup, no keys, no live-chain
transactions — the tests run entirely against a local fork. If the endpoint
rate-limits (HTTP 429), wait a minute and re-run, or substitute another public
Base RPC in the `createSelectFork` line — the block pin is what matters.

## What the tests assert

All actors are fresh unprivileged EOAs (no owner/admin/multisig impersonation
anywhere). Assertions are on the victim's locked principal.

- `test_C1_LockExtensionTrapsStakerPrincipal` — admin creates a subnet with the
  deployed-minimum 7-day lock; a victim stakes 100 MOR; at t0+1d the admin edits
  the lock to 100 years. At t0+8d (original term matured) and at t0+10 years the
  victim's full and partial withdrawals revert `BU: user withdraw is locked` and
  the 100 MOR is still staked. Control: an identical stake in a never-edited
  subnet withdraws in full at t0+8d; when the attacker edits the lock back to
  7 days the victim exits immediately — the trap is the admin's unilateral,
  reversible discretion.
- `test_C1b_LockExtensionOverflowVariant` — lock set to `type(uint128).max`
  makes `withdraw()` revert unconditionally (panic 0x11 overflow) for every staker.
- `test_C2_MinimalDepositRaiseBlocksPartialWithdraw` — second leg of the same
  edit vector: raising `minimalDeposit` post-deposit blocks partial withdrawals
  (`BU: invalid withdraw amount`); full exit still works.

## Expected output

```
Ran 3 tests for test/ForkLane4.t.sol:ForkLane4Test
[PASS] test_C1_LockExtensionTrapsStakerPrincipal() (gas: ...)
[PASS] test_C1b_LockExtensionOverflowVariant() (gas: ...)
[PASS] test_C2_MinimalDepositRaiseBlocksPartialWithdraw() (gas: ...)
Suite result: ok. 3 passed; 0 failed; 0 skipped
```

## Layout

- `test/ForkLane4.t.sol` — the PoC (candidate tests only).
- `src/Ifaces.sol` — minimal hand-written interfaces for the deployed contracts,
  derived from the Sourcify-verified deployed source.
- `lib/forge-std/` — forge-std v1.17.0 (vendored).
