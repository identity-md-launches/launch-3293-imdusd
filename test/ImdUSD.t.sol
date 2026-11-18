// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ImdUSD} from "../src/ImdUSD.sol";

/// @notice Stands in for whatever deploys the token (the launch factory deploys through CREATE2 and
/// then pays the supply out). It has no connection to the test contract's own address.
contract DeployerStandIn {
    function deploy(bytes32 salt) external returns (ImdUSD token) {
        token = new ImdUSD{salt: salt}();
    }

    function move(ImdUSD token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract ImdUSDTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000e18;

    ImdUSD internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        vm.prank(deployer);
        token = new ImdUSD();
    }

    // ---------------------------------------------------------------- metadata and supply

    function test_metadata() public view {
        assertEq(token.name(), "imdUSD");
        assertEq(token.symbol(), "IMDUSD");
        assertEq(token.decimals(), 18);
    }

    function test_supplyIsOneBillionWith18Decimals() public view {
        assertEq(token.SUPPLY(), EXPECTED_SUPPLY);
        assertEq(token.SUPPLY(), 1_000_000_000 * 10 ** uint256(token.decimals()));
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        // The literal the launch manifest states, digit for digit.
        assertEq(vm.toString(token.totalSupply()), "1000000000000000000000000000");
    }

    function test_wholeSupplyIsMintedToTheDeployer() public view {
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_constructorEmitsOneMintTransfer() public {
        vm.recordLogs();
        vm.prank(alice);
        ImdUSD fresh = new ImdUSD();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one event at construction");
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
        assertEq(logs[0].topics[1], bytes32(0), "minted from the zero address");
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), EXPECTED_SUPPLY);
    }

    /// @dev A factory deploying through CREATE2 receives the supply itself: `msg.sender`, not
    /// `tx.origin` and not the account that called the factory.
    function test_supplyGoesToADeployingContractNotToItsCaller() public {
        DeployerStandIn factory = new DeployerStandIn();
        vm.prank(alice, bob);
        ImdUSD fresh = factory.deploy(bytes32(uint256(7)));
        assertEq(fresh.totalSupply(), EXPECTED_SUPPLY);
        assertEq(fresh.balanceOf(address(factory)), EXPECTED_SUPPLY);
        assertEq(fresh.balanceOf(alice), 0);
        assertEq(fresh.balanceOf(bob), 0);
    }

    /// @dev The launch's own flows, with stand-in recipients: 10% to a distributor, 80% to a pool,
    /// the rest to the requester, and a claim out of the distributor. Each arrives whole.
    function test_launchStylePayoutsArriveWhole() public {
        DeployerStandIn factory = new DeployerStandIn();
        ImdUSD fresh = factory.deploy(bytes32(uint256(1)));
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address requester = makeAddr("requester");

        uint256 swarm = EXPECTED_SUPPLY * 1_000 / 10_000;
        uint256 seed = EXPECTED_SUPPLY * 8_000 / 10_000;
        uint256 rest = EXPECTED_SUPPLY - swarm - seed;

        assertTrue(factory.move(fresh, distributor, swarm));
        assertTrue(factory.move(fresh, pool, seed));
        assertTrue(factory.move(fresh, requester, rest));
        assertEq(fresh.balanceOf(distributor), swarm);
        assertEq(fresh.balanceOf(pool), seed);
        assertEq(fresh.balanceOf(requester), rest);
        assertEq(fresh.balanceOf(address(factory)), 0);

        vm.prank(distributor);
        assertTrue(fresh.transfer(carol, swarm));
        assertEq(fresh.balanceOf(carol), swarm);
        assertEq(fresh.balanceOf(distributor), 0);
        assertEq(fresh.totalSupply(), EXPECTED_SUPPLY);
    }

    // ---------------------------------------------------------------- transfer

    function test_transferMovesExactlyTheAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, 123e18);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 123e18));
        assertEq(token.balanceOf(alice), 123e18);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - 123e18);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_transferOfZeroSucceedsAndChangesNothing() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfLeavesBalanceUnchanged() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, 5e18));
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_transferRevertsWhenBalanceIsShort() public {
        vm.prank(deployer);
        token.transfer(alice, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(alice);
        token.transfer(bob, 11);
        assertEq(token.balanceOf(alice), 10);
    }

    function test_transferRevertsForMoreThanTheWholeSupply() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, deployer, EXPECTED_SUPPLY, EXPECTED_SUPPLY + 1
            )
        );
        vm.prank(deployer);
        token.transfer(alice, EXPECTED_SUPPLY + 1);
    }

    /// @dev Sending to the zero address would be a burn in disguise; the supply cannot shrink this way.
    function test_transferToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    // ---------------------------------------------------------------- approve and transferFrom

    function test_approveSetsAndOverwritesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(deployer, alice, 50);
        vm.prank(deployer);
        assertTrue(token.approve(alice, 50));
        assertEq(token.allowance(deployer, alice), 50);
        vm.prank(deployer);
        token.approve(alice, 7);
        assertEq(token.allowance(deployer, alice), 7);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 100);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 60));
        assertEq(token.balanceOf(bob), 60);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, alice), 40);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - 60);
    }

    function test_transferFromLeavesAnUnlimitedAllowanceUntouched() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 60);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_transferFromRevertsBeyondAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 100, 101));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 101);
        assertEq(token.allowance(deployer, alice), 100);
    }

    function test_transferFromRevertsWhenOwnerBalanceIsShort() public {
        vm.prank(alice);
        token.approve(bob, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 100));
        vm.prank(bob);
        token.transferFrom(alice, bob, 100);
    }

    /// @dev Not even the original deployer can pull a holder's tokens without that holder's approval.
    function test_deployerHasNoPowerOverAHoldersBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 1_000);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 1_000);
    }

    // ---------------------------------------------------------------- no privileged surface

    /// @dev None of these functions exist, so every call reverts and nothing changes, whether it
    /// comes from the deployer or a stranger.
    function test_noMintBurnOwnerOrFreezeFunctionExists() public {
        vm.prank(deployer);
        token.transfer(alice, 1_000);

        string[26] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "burn(uint256)",
            "burn(address,uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "setOwner(address)",
            "transferOwnership(address)",
            "renounceOwnership()",
            "setMinter(address)",
            "upgradeTo(address)",
            "upgradeToAndCall(address,bytes)",
            "initialize(address)",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "seize(address)"
        ];
        address[2] memory callers = [deployer, carol];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, uint256(1));
            for (uint256 j = 0; j < callers.length; j++) {
                vm.prank(callers[j]);
                (bool ok,) = address(token).call(data);
                assertFalse(ok, signatures[i]);
            }
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(alice), 1_000);
        assertEq(token.balanceOf(carol), 0);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 400), "the holder can still transfer");
        assertEq(token.balanceOf(bob), 400);
    }

    function test_rejectsEtherAndUnknownCalls() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "plain ether must be refused");
        vm.prank(alice);
        (ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok, "there is no fallback");
        assertEq(address(token).balance, 0);
    }

    /// @dev Reachable runtime code holds no DELEGATECALL, CALLCODE, SELFDESTRUCT, nor any CALL,
    /// STATICCALL, CREATE or CREATE2: the token never calls out and cannot be replaced.
    function test_runtimeCodeMakesNoExternalCalls() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "EIP-170");
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
                assertTrue(op != 0xF1, "CALL");
                assertTrue(op != 0xFA, "STATICCALL");
                assertTrue(op != 0xF0, "CREATE");
                assertTrue(op != 0xF5, "CREATE2");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferConservesBalances(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        } else {
            assertEq(token.balanceOf(to), toBefore + amount);
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - amount);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(address from, address to, uint256 held, uint256 excess) public {
        vm.assume(from != address(0) && to != address(0) && from != deployer);
        held = bound(held, 0, EXPECTED_SUPPLY);
        excess = bound(excess, 1, type(uint256).max - held);
        vm.prank(deployer);
        token.transfer(from, held);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, held + excess)
        );
        vm.prank(from);
        token.transfer(to, held + excess);
    }

    function testFuzz_transferFromSpendsExactly(address spender, address to, uint256 allowed, uint256 amount) public {
        vm.assume(spender != address(0) && to != address(0) && to != deployer);
        allowed = bound(allowed, 0, type(uint256).max - 1);
        amount = bound(amount, 0, allowed < EXPECTED_SUPPLY ? allowed : EXPECTED_SUPPLY);
        vm.prank(deployer);
        token.approve(spender, allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - amount);
        // When the deployer approves itself the allowance is still spent like any other.
        assertEq(token.allowance(deployer, spender), allowed - amount);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_transferFromAboveAllowanceReverts(address spender, uint256 allowed, uint256 amount) public {
        vm.assume(spender != address(0));
        allowed = bound(allowed, 0, EXPECTED_SUPPLY - 1);
        amount = bound(amount, allowed + 1, EXPECTED_SUPPLY);
        vm.prank(deployer);
        token.approve(spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, amount);
    }

    function testFuzz_everyDeploymentMintsTheSameSupplyToItsDeployer(address anyDeployer) public {
        vm.assume(anyDeployer != address(0));
        vm.prank(anyDeployer);
        ImdUSD fresh = new ImdUSD();
        assertEq(fresh.totalSupply(), EXPECTED_SUPPLY);
        assertEq(fresh.balanceOf(anyDeployer), EXPECTED_SUPPLY);
    }
}
