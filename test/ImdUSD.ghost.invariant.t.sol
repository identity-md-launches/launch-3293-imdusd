// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ImdUSD} from "../src/ImdUSD.sol";

/// @notice Drives random transfers, approvals, pulls and refused calls across several actors (the
/// token's own address among them) and keeps an independent ledger of what every balance and
/// allowance should be. The handler never reverts: refused calls are made with low-level calls and
/// must fail without changing anything.
contract GhostHandler is Test {
    ImdUSD public immutable token;
    address[] public actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;
    uint256 public refusedCalls;
    uint256 public unexpectedSuccesses;

    constructor() {
        token = new ImdUSD();
        actors.push(address(this));
        actors.push(address(token));
        for (uint256 i = 1; i <= 6; i++) {
            actors.push(address(uint160(0xB0B000 + i)));
        }
        ghostBalance[address(this)] = token.SUPPLY();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        token.transfer(to, amount);
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (unlimited) amount = type(uint256).max;
        vm.prank(owner);
        token.approve(spender, amount);
        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 held = ghostBalance[owner];
        amount = bound(amount, 0, allowed < held ? allowed : held);
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
        ghostBalance[owner] -= amount;
        ghostBalance[to] += amount;
    }

    /// @dev A pull for more than the allowance (and within the balance or not) is refused.
    function pullBeyondAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 excess) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        if (allowed == type(uint256).max) return;
        excess = bound(excess, 1, type(uint256).max - allowed);
        _expectRefused(spender, abi.encodeCall(token.transferFrom, (owner, actors[0], allowed + excess)));
    }

    function overspend(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        uint256 held = ghostBalance[from];
        excess = bound(excess, 1, type(uint256).max - held);
        _expectRefused(from, abi.encodeCall(token.transfer, (_actor(toSeed), held + excess)));
    }

    function sendToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        _expectRefused(from, abi.encodeCall(token.transfer, (address(0), amount)));
    }

    function _expectRefused(address caller, bytes memory data) private {
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        if (ok) unexpectedSuccesses++;
        refusedCalls++;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }
}

contract ImdUSDGhostInvariantTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000e18;

    GhostHandler internal handler;
    ImdUSD internal token;

    function setUp() public {
        handler = new GhostHandler();
        token = handler.token();
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 128
    function invariant_balancesMatchTheLedger() public view {
        uint256 n = handler.actorCount();
        uint256 sum;
        for (uint256 i = 0; i < n; i++) {
            address a = handler.actors(i);
            assertEq(token.balanceOf(a), handler.ghostBalance(a), "balance drifted from the ledger");
            sum += token.balanceOf(a);
        }
        assertEq(sum, EXPECTED_SUPPLY, "tokens left the closed set of actors");
    }

    /// forge-config: default.invariant.runs = 128
    function invariant_allowancesMatchTheLedger() public view {
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = 0; j < n; j++) {
                address o = handler.actors(i);
                address s = handler.actors(j);
                assertEq(token.allowance(o, s), handler.ghostAllowance(o, s), "allowance drifted from the ledger");
            }
        }
    }

    /// forge-config: default.invariant.runs = 128
    function invariant_supplyFixedAndRefusalsHold() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(handler.unexpectedSuccesses(), 0, "a call that must be refused went through");
    }
}
