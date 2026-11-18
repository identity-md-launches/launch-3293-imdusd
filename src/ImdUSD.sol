// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title imdUSD (IMDUSD)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 tokens (18 decimals) is minted
/// once, in the constructor, to the account that deploys the contract. Nothing can mint again.
/// @dev The Solidity identifier is `ImdUSD`; the token's name is `imdUSD` and its symbol `IMDUSD`.
/// There is deliberately no owner, no minter, no pause, no blacklist, no fee on transfer, no burn
/// function, no upgrade path and no external call: after the constructor the contract is plain
/// OpenZeppelin v5 ERC-20 accounting. Despite the name, the contract holds no reserve and enforces
/// no peg; see the README.
contract ImdUSD is ERC20 {
    /// @notice The whole supply, in the token's smallest unit: 1,000,000,000 * 10^18.
    uint256 public constant SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints `SUPPLY` to the deployer. When a factory deploys the token the deployer is that
    /// factory (`msg.sender`), never `tx.origin`.
    constructor() ERC20("imdUSD", "IMDUSD") {
        _mint(msg.sender, SUPPLY);
    }
}
