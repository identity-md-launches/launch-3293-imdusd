// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ImdUSD} from "../src/ImdUSD.sol";

/// @notice Drives random transfers, approvals and pulls between a closed set of holders. The handler
/// deploys the token itself, so it starts with the whole supply.
contract ImdUSDHandler is Test {
    ImdUSD public immutable token;
    address[] public holders;
    uint256 public calls;

    constructor() {
        token = new ImdUSD();
        holders.push(address(this));
        for (uint256 i = 1; i <= 5; i++) {
            holders.push(address(uint160(0xA11CE000 + i)));
        }
    }

    function holderCount() external view returns (uint256) {
        return holders.length;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _holder(fromSeed);
        address to = _holder(toSeed);
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        token.transfer(to, amount);
        calls++;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        vm.prank(_holder(ownerSeed));
        token.approve(_holder(spenderSeed), amount);
        calls++;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _holder(ownerSeed);
        address spender = _holder(spenderSeed);
        address to = _holder(toSeed);
        uint256 allowed = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        amount = bound(amount, 0, allowed < balance ? allowed : balance);
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        if (allowed != type(uint256).max) {
            assertEq(token.allowance(owner, spender), allowed - amount, "allowance not spent exactly");
        }
        calls++;
    }

    /// @dev An over-spend must always revert and must never be absorbed.
    function overspend(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _holder(fromSeed);
        uint256 balance = token.balanceOf(from);
        excess = bound(excess, 1, type(uint256).max - balance);
        vm.prank(from);
        try token.transfer(_holder(toSeed), balance + excess) {
            revert("an over-spend went through");
        } catch {}
        calls++;
    }

    function _holder(uint256 seed) private view returns (address) {
        return holders[seed % holders.length];
    }
}

contract ImdUSDInvariantTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000e18;

    ImdUSDHandler internal handler;
    ImdUSD internal token;

    function setUp() public {
        handler = new ImdUSDHandler();
        token = handler.token();
        targetContract(address(handler));
    }

    /// @dev The supply never grows and never shrinks.
    function invariant_totalSupplyIsConstant() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    /// @dev Tokens only move inside the closed set of holders, so their balances always sum to the
    /// supply: nothing is created, destroyed or stranded by a transfer.
    function invariant_balancesSumToTheSupply() public view {
        uint256 sum;
        uint256 count = handler.holderCount();
        for (uint256 i = 0; i < count; i++) {
            sum += token.balanceOf(handler.holders(i));
        }
        assertEq(sum, EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
