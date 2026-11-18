# Vendored libraries

Ordinary files, not git submodules, copied unmodified from the upstream release tags.

| Path                         | Upstream                                           | Tag    | What is included |
| ---------------------------- | -------------------------------------------------- | ------ | ---------------- |
| `forge-std/`                 | https://github.com/foundry-rs/forge-std            | v1.9.7 | `src/`, licences, `package.json`, README |
| `openzeppelin-contracts/`    | https://github.com/OpenZeppelin/openzeppelin-contracts | v5.4.0 | `LICENSE` and the five files `ERC20` compiles from |

OpenZeppelin files included, relative to `openzeppelin-contracts/contracts/`:

- `token/ERC20/ERC20.sol`
- `token/ERC20/IERC20.sol`
- `token/ERC20/extensions/IERC20Metadata.sol`
- `utils/Context.sol`
- `interfaces/draft-IERC6093.sol`

To update, replace the files with the same paths from a newer tag and re-run `forge test`.
