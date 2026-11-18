// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ImdUSD} from "../src/ImdUSD.sol";
import {WalletGas} from "./WalletGas.sol";

/// @notice Edge inputs and failure paths the main unit suite does not reach, plus the wallet-gas check
/// for every function a holder or a bot sends.
contract ImdUSDEdgesTest is WalletGas {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000e18;

    ImdUSD internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.prank(deployer);
        token = new ImdUSD();
    }

    // ---------------------------------------------------------------- wallet gas

    /// @dev The token neither checks gasleft(), forwards fixed gas nor catches a failed call; each
    /// state-changing entry point still does exactly the same at the lowest non-reverting gas limit.
    function test_transferSameAtWalletGas() public {
        assertSameAtWalletGas(deployer, address(token), abi.encodeCall(IERC20.transfer, (alice, 1e18)));
        // A first transfer into an empty slot and a full-balance transfer that empties one.
        vm.prank(deployer);
        token.transfer(alice, 5e18);
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(IERC20.transfer, (bob, 5e18)));
    }

    function test_approveSameAtWalletGas() public {
        assertSameAtWalletGas(deployer, address(token), abi.encodeCall(IERC20.approve, (alice, 100)));
        assertSameAtWalletGas(deployer, address(token), abi.encodeCall(IERC20.approve, (alice, type(uint256).max)));
    }

    function test_transferFromSameAtWalletGas() public {
        vm.prank(deployer);
        token.approve(alice, 100);
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(IERC20.transferFrom, (deployer, bob, 60)));
        vm.prank(deployer);
        token.approve(bob, type(uint256).max);
        assertSameAtWalletGas(bob, address(token), abi.encodeCall(IERC20.transferFrom, (deployer, alice, 1e18)));
    }

    // ---------------------------------------------------------------- zero-address failure paths

    function test_transferFromZeroAddressSenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
    }

    function test_approveFromZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(alice, 1);
    }

    /// @dev Pulling "from" the zero address with a zero amount passes the allowance check and must
    /// still be refused: the zero address is never a source of tokens. OpenZeppelin v5 spends (and
    /// re-writes) the allowance first, so the zero owner is refused there as an invalid approver.
    function test_transferFromTheZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(alice);
        token.transferFrom(address(0), bob, 0);
    }

    function test_transferFromToZeroAddressReverts() public {
        vm.prank(deployer);
        token.approve(alice, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transferFrom(deployer, address(0), 10);
        assertEq(token.allowance(deployer, alice), 10, "a reverted pull spends no allowance");
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    // ---------------------------------------------------------------- allowance edges

    /// @dev max - 1 is a finite allowance and is spent; only exactly max is treated as unlimited.
    function test_allowanceOneBelowMaxIsSpent() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max - 1);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, alice), type(uint256).max - 2);
    }

    function test_allowanceSpentToExactlyZeroThenRefuses() public {
        vm.prank(deployer);
        token.approve(alice, 7);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 7);
        assertEq(token.allowance(deployer, alice), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.balanceOf(bob), 7);
    }

    function test_revokedAllowanceCannotBeUsed() public {
        vm.prank(deployer);
        token.approve(alice, 1_000);
        vm.prank(deployer);
        token.approve(alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(deployer, alice, 1);
    }

    /// @dev Pulling your own tokens through transferFrom still needs an allowance to yourself.
    function test_selfPullNeedsSelfAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
        vm.prank(deployer);
        token.approve(deployer, 1);
        vm.prank(deployer);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, deployer), 0);
    }

    /// @dev A pull emits exactly one Transfer and no Approval event, finite allowance or not.
    function test_transferFromEmitsOnlyTransfer() public {
        vm.prank(deployer);
        token.approve(alice, 100);
        vm.recordLogs();
        vm.prank(alice);
        token.transferFrom(deployer, bob, 40);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(deployer))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(bob))));
        assertEq(abi.decode(logs[0].data, (uint256)), 40);
    }

    /// @dev Tokens sent to the token contract itself are stuck (no rescue), but they are not burned:
    /// the supply is unchanged and nobody gains or loses beyond the sender.
    function test_transferToTheTokenItselfIsNotABurn() public {
        vm.prank(deployer);
        token.transfer(address(token), 3e18);
        assertEq(token.balanceOf(address(token)), 3e18);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    // ---------------------------------------------------------------- whole-supply edges

    function test_wholeSupplyMovesAndComesBack() public {
        vm.prank(deployer);
        token.transfer(alice, EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), EXPECTED_SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transfer(alice, 1);
        vm.prank(alice);
        token.transfer(deployer, EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_unlimitedAllowanceStillCappedByBalance() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, deployer, EXPECTED_SUPPLY, EXPECTED_SUPPLY + 1
            )
        );
        vm.prank(alice);
        token.transferFrom(deployer, bob, EXPECTED_SUPPLY + 1);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    // ---------------------------------------------------------------- fuzz

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveRoundTrips(address owner, address spender, uint256 amount) public {
        owner = address(uint160(bound(uint160(owner), 1, type(uint160).max)));
        spender = address(uint160(bound(uint160(spender), 1, type(uint160).max)));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(owner, spender, amount);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    /// @dev A transfer between two holders touches no third account.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferTouchesOnlySenderAndReceiver(uint256 amount, address bystander) public {
        vm.assume(bystander != deployer && bystander != alice);
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        uint256 before = token.balanceOf(bystander);
        vm.prank(deployer);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(bystander), before);
    }

    /// @dev Any failing transfer leaves every balance and allowance as it was.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_failedPullChangesNothing(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, EXPECTED_SUPPLY);
        amount = bound(amount, allowed + 1, type(uint256).max);
        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        (bool ok,) = address(token).call(abi.encodeCall(IERC20.transferFrom, (deployer, bob, amount)));
        assertFalse(ok);
        assertEq(token.allowance(deployer, alice), allowed);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }
}
