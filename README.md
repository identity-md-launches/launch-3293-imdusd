# imdUSD (IMDUSD)

A fixed-supply ERC-20 for a custom token launch on Ethereum mainnet (chain id 1).

| Property        | Value                                                              |
| --------------- | ------------------------------------------------------------------ |
| Token name      | `imdUSD`                                                           |
| Token symbol    | `IMDUSD`                                                           |
| Decimals        | 18                                                                 |
| Total supply    | 1,000,000,000 tokens = `1000000000000000000000000000` minor units  |
| Solidity name   | `ImdUSD` (`src/ImdUSD.sol`)                                        |
| Constructor     | no arguments                                                       |
| Minting         | once, in the constructor, the whole supply to `msg.sender`         |
| Owner / admin   | none                                                               |

## What the contract does

`ImdUSD` is OpenZeppelin Contracts v5.4.0 `ERC20` with one addition: the constructor mints the
constant `SUPPLY` (1,000,000,000 × 10^18) to the account that deploys it. That is the only mint.
After the constructor the contract is plain ERC-20 accounting:

- `transfer`, `approve`, `transferFrom`, `balanceOf`, `allowance`, `totalSupply`, `name`, `symbol`,
  `decimals`, and the public constant `SUPPLY`.
- Transfers move exactly the amount asked for. There is no fee, tax, burn, rebase or reflection, and
  no address is treated differently from any other.
- A transfer to the zero address reverts, so the supply can neither grow nor shrink: `totalSupply()`
  is 1,000,000,000 × 10^18 forever.

What it deliberately does not have: an owner, a minter, a burn function, pause, blacklist or freeze,
`permit`, an upgrade path or proxy, a fallback or `receive`, or any call to another contract. The
runtime bytecode contains no `CALL`, `STATICCALL`, `DELEGATECALL`, `CALLCODE`, `CREATE`, `CREATE2` or
`SELFDESTRUCT` (a test checks this), so reentrancy through the token is not possible.

## Assumptions

These are the choices made where the brief was silent. Each is the narrowest reading of "a custom
token with this name, symbol and supply".

1. **No peg.** The name contains "USD", but the brief asks for a fixed supply minted once and
   nothing else, so the contract holds no reserve, has no mint/redeem, reads no oracle and enforces
   no price. Nothing on chain makes one IMDUSD worth one US dollar. The launch opens the pool at a
   2,500 IMD market capitalisation for the whole supply, i.e. 0.0000025 IMD per token. Anyone
   presenting the token to holders is responsible for not describing it as a redeemable or
   collateralised dollar stablecoin.
2. **"The deployer" is `msg.sender` of the creation.** In the launch that is the factory, which pays
   the whole supply out in the launch transaction. `tx.origin` is never used.
3. **No extras.** Burning, EIP-2612 `permit`, voting checkpoints, transfer hooks and admin powers
   were not requested and are not included. Adding any of them later is impossible: the contract is
   not upgradeable.
4. **Standard ERC-20 semantics** as implemented by OpenZeppelin v5: custom errors from ERC-6093
   (`ERC20InsufficientBalance`, `ERC20InsufficientAllowance`, `ERC20InvalidReceiver`,
   `ERC20InvalidSpender`, …), an allowance of `type(uint256).max` is treated as unlimited and is not
   decremented, and `transfer`/`transferFrom` return `true` or revert.

## Deployment parameters

The token takes no constructor arguments; everything is a constant in the source.

| Parameter (for the launch manifest step) | Value                                          |
| ---------------------------------------- | ---------------------------------------------- |
| `token.contract`                         | `ImdUSD`                                       |
| `token.name`                             | `imdUSD`                                       |
| `token.symbol`                           | `IMDUSD`                                       |
| `token.decimals`                         | `18`                                           |
| `token.totalSupply`                      | `1000000000000000000000000000`                 |
| `token.constructorArgs`                  | none                                           |
| Application contracts                    | none                                           |

Launch terms, decided by the launch and the requester and repeated here only for context (the token
neither knows nor depends on any of them):

- Chain: Ethereum, chain id 1. Pair: IMD (`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, 18 decimals).
- Pool: fee `12500` (1.25%), tick spacing `60`.
- Economics: `poolBps` 8000, `initialMarketCapWei` `2500000000000000000000` (2,500 IMD),
  `remainderTo` `0xd6302976e590b9b947da8774b7f1246164e0ce98`.
- Distribution of the supply by the factory: 10% (100,000,000) to the launch's MerkleDistributor for
  the swarm, 80% (800,000,000) seeds the pool single-sided, 10% (100,000,000) to `remainderTo`.

No `launch.json` is included: the manifest step writes it. No deploy script is included either: the
launch deploys the token from its built bytecode through the factory, and this repository broadcasts
nothing and holds no key.

Because the token exempts nobody and taxes nothing, the launch flows are exact by construction: the
swarm's share, the pool seed, the remainder, distributor claims and swaps through the Uniswap v4
PoolManager all move precisely the amounts they state.

### Build settings (needed to reproduce the bytecode)

From `foundry.toml`: `solc = "0.8.26"`, `evm_version = "cancun"`, optimizer on with 200 runs,
`bytecode_hash = "none"`. No `ffi`, no filesystem permissions, no libraries to link.

## After launch

Nothing. The contract has no settings, no setters and no owner, so there is no post-deployment
configuration and no key to safeguard for the token itself.

## Operational responsibilities

- **Nobody administers the token.** There is no role that can mint, pause, freeze, seize, upgrade or
  recover. This is a guarantee to holders and also a limit: mistakes cannot be undone by anyone.
- **Whoever receives supply is its custodian.** The deployer holds 100% of the supply at the end of
  the constructor. In the launch the factory distributes it in the same transaction; the holder of
  `remainderTo` (10%) is then responsible for that wallet's security and for any vesting, treasury
  or distribution policy it wants, none of which the token enforces.
- **Tokens sent to the wrong place are lost.** Tokens sent to the token contract itself, or to any
  contract that cannot send them on, cannot be rescued: there is no sweep function because there is
  nobody who could be trusted to call it.
- **Allowances.** `approve` overwrites the previous allowance (the well-known ERC-20 ordering
  caveat). Integrators should approve exact amounts or reset to zero before changing a non-zero
  allowance, and should avoid unlimited approvals to contracts they do not trust.
- **Integrators** should read `decimals()` (18) rather than assume it, and may rely on balances
  changing only through `Transfer` events (no rebasing, no fee on transfer).
- **Open items for the network's deployer:** explorer source verification with the build settings
  above. There are no upgrade rights or ownership to hand over.

## Tests

```sh
forge build
forge test
forge fmt --check
```

`test/ImdUSD.t.sol` (unit and fuzz):

- metadata, the exact supply literal, the whole supply minted to the deployer with a single mint
  event, and to a deploying contract rather than its caller or `tx.origin`;
- a launch-style payout (10% / 80% / 10%, then a claim) arriving whole with the supply unchanged;
- transfers: exact movement, zero amount, self-transfer; failures for a short balance, more than the
  supply, and the zero address;
- allowances: set and overwrite, exact spending, unlimited allowance left untouched; failures for no
  allowance, an exceeded allowance, a short owner balance, a zero spender, and the deployer trying
  to pull a holder's tokens;
- no privileged surface: 26 common mint/burn/owner/upgrade/pause/freeze selectors all revert from
  both the deployer and a stranger, ether and unknown calls are refused, and the runtime bytecode is
  scanned for call, create and self-destruct opcodes;
- fuzz tests for conservation on `transfer` and `transferFrom` and for both over-spend reverts.

`test/ImdUSD.invariant.t.sol`: a handler drives random transfers, approvals, pulls and attempted
over-spends between a closed set of holders; the invariants are that `totalSupply()` never changes
and that the holders' balances always sum to it.

Tests read no environment variables, use no fork and no `ffi`, and do not depend on execution order.

## Security notes

- Checked against the `eth-security` checklist: access control (there is none to get wrong),
  reentrancy (no external calls), input validation (zero-address checks inherited from
  OpenZeppelin), decimals (18, fixed), upgradeability (none), infinite approvals (documented above).
- Written to stay clear of the Slither detectors the verifier rejects on: no `selfdestruct`,
  `transferFrom` spends the caller's allowance only, no initializer or upgrade path, no storage
  pointers, no assembly shifts, no `abi.encodePacked`.
- Tools run for this work: `forge build`, `forge test` (including the fuzz and invariant suites) and
  `forge fmt --check`. Slither and Mythril were not run here.
- Passing tests are not an audit. The token is small and built on audited library code, but an
  independent review before release is still the network's stated practice.

## Vendored dependencies

Committed as ordinary files under `lib/` (no git submodules), so the project builds offline:

- `lib/forge-std` — forge-std v1.9.7 (`src/` only), MIT / Apache-2.0. Test-only.
- `lib/openzeppelin-contracts` — the five files of OpenZeppelin Contracts v5.4.0 that `ERC20`
  needs (`ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol`),
  unmodified, MIT. See `lib/README.md`.
