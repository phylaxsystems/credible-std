// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {KyberMetaAggregationRouterAssertion} from "../src/KyberMetaAggregationRouterAssertion.sol";
import {SwapDescriptionV2, SwapExecutionParams} from "../src/KyberMetaAggregationRouterInterfaces.sol";
import {
    FeeOnTransferToken,
    MintableToken,
    MockAggregationExecutor,
    MockKyberRouterV2,
    MockUniV2Pool,
    PermitMintableToken,
    SelfFundedPayer
} from "./KyberSwapMocks.sol";

/// @notice Extensive behavior tests for the KyberSwap router assertions.
/// @dev Drives the assertions through a faithful MetaAggregationRouterV2 settlement model:
///      standing-allowance pulls to srcReceivers/feeReceivers, executor dispatch via low-level
///      call, a constant-product pool, fee-on-transfer tokens, swapSimpleMode, and the real
///      arbitrary-call allowance-drain vector. Each test arms one assertion and exercises one
///      honest path or one failure mode.
contract KyberMetaAggregationRouterAssertionTest is Test, CredibleTest {
    address internal constant ETH_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    MintableToken internal src;
    MintableToken internal dst;
    MockKyberRouterV2 internal router;
    MockAggregationExecutor internal executor;
    MockUniV2Pool internal pool;

    address internal recipient = makeAddr("recipient");
    address internal feeWallet = makeAddr("feeWallet");
    address internal victim = makeAddr("victim");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant LIQUIDITY = 1_000_000 ether;
    uint256 internal constant AMOUNT_IN = 10 ether;

    function setUp() public {
        src = new MintableToken("Src", "SRC");
        dst = new MintableToken("Dst", "DST");
        router = new MockKyberRouterV2();
        executor = new MockAggregationExecutor();

        pool = new MockUniV2Pool(address(src), address(dst));
        src.mint(address(pool), LIQUIDITY);
        dst.mint(address(pool), LIQUIDITY);
        pool.sync();

        // The test contract is the swap initiator and approves the router for its own pulls.
        src.mint(address(this), 1_000 ether);
        src.approve(address(router), type(uint256).max);
    }

    // ---------------------------------------------------------------
    //  Helpers
    // ---------------------------------------------------------------

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData = abi.encodePacked(
            type(KyberMetaAggregationRouterAssertion).creationCode, abi.encode(address(router), true)
        );
        cl.assertion(address(router), createData, fnSelector);
    }

    function _armDrain() internal {
        _arm(KyberMetaAggregationRouterAssertion.assertNoThirdPartyAllowanceDrain.selector);
    }

    function _armMinReturn() internal {
        _arm(KyberMetaAggregationRouterAssertion.assertReceiverGetsMinReturn.selector);
    }

    function _one(address a) internal pure returns (address[] memory r) {
        r = new address[](1);
        r[0] = a;
    }

    function _one(uint256 v) internal pure returns (uint256[] memory r) {
        r = new uint256[](1);
        r[0] = v;
    }

    function _noAddrs() internal pure returns (address[] memory r) {
        r = new address[](0);
    }

    function _noUints() internal pure returns (uint256[] memory r) {
        r = new uint256[](0);
    }

    /// @notice Builds the executor calldata for an honest pool swap of `src` into `to`.
    function _executorData(address to) internal view returns (bytes memory) {
        return abi.encodeCall(MockAggregationExecutor.callBytes, (abi.encode(address(pool), address(src), to)));
    }

    function _expectedOut() internal view returns (uint256) {
        return pool.getAmountOut(AMOUNT_IN, pool.reserve0(), pool.reserve1());
    }

    function _expectedOutFor(uint256 amountIn) internal view returns (uint256) {
        return pool.getAmountOut(amountIn, pool.reserve0(), pool.reserve1());
    }

    uint256 internal constant PARTIAL_FILL = 0x01;

    /// @notice An honest single-hop swap: pull src from initiator to the pool, then swap to `to`.
    function _honestParams(address dstToken, address to, uint256 minReturn)
        internal
        view
        returns (SwapExecutionParams memory p)
    {
        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = dstToken;
        desc.srcReceivers = _one(address(pool));
        desc.srcAmounts = _one(AMOUNT_IN);
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = to;
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = minReturn;

        p.callTarget = address(executor);
        p.targetData = _executorData(to);
        p.desc = desc;
    }

    /// @notice A bare swap that performs only the arbitrary executor call (no real pool leg).
    function _arbitraryCallParams(address callTarget, bytes memory targetData)
        internal
        view
        returns (SwapExecutionParams memory p)
    {
        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(dst);
        desc.srcReceivers = _noAddrs();
        desc.srcAmounts = _noUints();
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = recipient;
        desc.amount = 0;
        desc.minReturnAmount = 0;

        p.callTarget = callTarget;
        p.targetData = targetData;
        p.desc = desc;
    }

    // ===============================================================
    //  assertReceiverGetsMinReturn — execution safety
    // ===============================================================

    /// @notice Honest pool swap delivers at least the signed minimum.
    function testMinReturn_HonestV2Swap_Passes() public {
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, _expectedOut());

        _armMinReturn();
        router.swap(p);
    }

    /// @notice Recipient credited exactly the minimum is acceptable (>= boundary).
    function testMinReturn_ExactBoundary_Passes() public {
        uint256 out = _expectedOut();
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, out);

        _armMinReturn();
        router.swap(p);
        assertEq(dst.balanceOf(recipient), out);
    }

    /// @notice The recipient is read from the description, not the caller.
    function testMinReturn_RecipientIsThirdParty_Passes() public {
        address thirdParty = makeAddr("thirdPartyRecipient");
        SwapExecutionParams memory p = _honestParams(address(dst), thirdParty, _expectedOut());

        _armMinReturn();
        router.swap(p);
        assertGt(dst.balanceOf(thirdParty), 0);
    }

    /// @notice A compromised router whose own min-return guard is absent cannot underpay silently.
    function testMinReturn_CompromisedRouterUnderpays_Trips() public {
        router.setEnforceMinReturn(false);
        uint256 unmetMinimum = _expectedOut() + 100 ether;
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, unmetMinimum);

        _armMinReturn();
        vm.expectRevert(bytes("Kyber: dstReceiver credited below minReturnAmount"));
        router.swap(p);
    }

    /// @notice A fee-on-transfer buy token credits the recipient less than the router-measured output.
    function testMinReturn_FeeOnTransferDstToken_Trips() public {
        FeeOnTransferToken fot = new FeeOnTransferToken(100, makeAddr("feeSink")); // 1% skim
        MockUniV2Pool fotPool = new MockUniV2Pool(address(src), address(fot));
        src.mint(address(fotPool), LIQUIDITY);
        fot.mint(address(fotPool), LIQUIDITY);
        fotPool.sync();

        uint256 grossOut = fotPool.getAmountOut(AMOUNT_IN, fotPool.reserve0(), fotPool.reserve1());

        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(fot);
        desc.srcReceivers = _one(address(fotPool));
        desc.srcAmounts = _one(AMOUNT_IN);
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = recipient;
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = grossOut; // router is satisfied by the gross output

        SwapExecutionParams memory p;
        p.callTarget = address(executor);
        p.targetData =
            abi.encodeCall(MockAggregationExecutor.callBytes, (abi.encode(address(fotPool), address(src), recipient)));
        p.desc = desc;

        _armMinReturn();
        vm.expectRevert(bytes("Kyber: dstReceiver credited below minReturnAmount"));
        router.swap(p);
    }

    /// @notice Native-asset payouts are out of scope and must not trip the ERC20-only check.
    function testMinReturn_NativeEthOut_Skipped_Passes() public {
        router.setEnforceMinReturn(false);
        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = ETH_SENTINEL;
        desc.srcReceivers = _noAddrs();
        desc.srcAmounts = _noUints();
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = recipient;
        desc.minReturnAmount = 1 ether;

        SwapExecutionParams memory p;
        p.desc = desc;

        _armMinReturn();
        router.swap(p);
    }

    /// @notice A zero minimum is a no-op for this assertion.
    function testMinReturn_ZeroMinReturn_Skipped_Passes() public {
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, 0);

        _armMinReturn();
        router.swap(p);
    }

    /// @notice swapSimpleMode honest path delivers the minimum.
    function testMinReturn_SwapSimpleMode_Honest_Passes() public {
        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(dst);
        desc.srcReceivers = _one(address(pool));
        desc.srcAmounts = _one(AMOUNT_IN);
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = recipient;
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = _expectedOut();

        _armMinReturn();
        router.swapSimpleMode(address(executor), desc, _executorData(recipient), "");
    }

    /// @notice swapGeneric honest path delivers at least the signed minimum.
    function testMinReturn_SwapGeneric_Honest_Passes() public {
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, _expectedOut());

        _armMinReturn();
        router.swapGeneric(p);
        assertGe(dst.balanceOf(recipient), _expectedOut());
    }

    /// @notice swapGeneric underpayment trips when the router guard is absent.
    function testMinReturn_SwapGeneric_Underpaid_Trips() public {
        router.setEnforceMinReturn(false);
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, _expectedOut() + 100 ether);

        _armMinReturn();
        vm.expectRevert(bytes("Kyber: dstReceiver credited below minReturnAmount"));
        router.swapGeneric(p);
    }

    /// @notice An unset dstReceiver is credited to msg.sender; an honest fill still passes.
    /// @dev The assertion resolves the empty recipient to the initiator instead of skipping, so
    ///      the default-recipient path (the common API shape) stays protected.
    function testMinReturn_UnsetReceiver_ResolvesToInitiator_Passes() public {
        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(dst);
        desc.srcReceivers = _one(address(pool));
        desc.srcAmounts = _one(AMOUNT_IN);
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = address(0); // router credits msg.sender (this contract)
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = _expectedOut();

        SwapExecutionParams memory p;
        p.callTarget = address(executor);
        p.targetData = _executorData(address(this)); // executor pays the resolved recipient

        p.desc = desc;

        uint256 before = dst.balanceOf(address(this));
        _armMinReturn();
        router.swap(p);
        // The initiator (msg.sender) is the resolved recipient and is credited at least the minimum.
        assertGe(dst.balanceOf(address(this)) - before, desc.minReturnAmount);
    }

    /// @notice An unset dstReceiver that underpays the initiator trips just like a named recipient.
    function testMinReturn_UnsetReceiver_Underpaid_Trips() public {
        router.setEnforceMinReturn(false);
        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(dst);
        desc.srcReceivers = _one(address(pool));
        desc.srcAmounts = _one(AMOUNT_IN);
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = address(0);
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = _expectedOut() + 100 ether;

        SwapExecutionParams memory p;
        p.callTarget = address(executor);
        p.targetData = _executorData(address(this));
        p.desc = desc;

        _armMinReturn();
        vm.expectRevert(bytes("Kyber: dstReceiver credited below minReturnAmount"));
        router.swap(p);
    }

    /// @notice A legitimate partial fill credits less than the flat minimum and must NOT trip.
    /// @dev The router holds a partial-fill order to a pro-rated minimum keyed to the amount
    ///      actually spent, so the recipient is correctly credited below `minReturnAmount`. A flat
    ///      `>= minReturnAmount` assertion would revert this valid swap; the assertion skips the
    ///      `_PARTIAL_FILL` flag for exactly this reason.
    function testMinReturn_PartialFill_NoFalsePositive_Passes() public {
        uint256 spent = AMOUNT_IN / 2;
        uint256 fullMinimum = _expectedOut(); // signed minimum for the full order size

        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(dst);
        desc.srcReceivers = _one(address(pool));
        desc.srcAmounts = _one(spent); // only half the order is actually filled
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = recipient;
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = fullMinimum;
        desc.flags = PARTIAL_FILL;

        SwapExecutionParams memory p;
        p.callTarget = address(executor);
        p.targetData = _executorData(recipient);
        p.desc = desc;

        _armMinReturn();
        router.swap(p); // router's pro-rated guard passes; assertion must not false-positive
        // The recipient is genuinely credited below the flat minimum — proving the skip is load-bearing.
        assertLt(dst.balanceOf(recipient), fullMinimum);
    }

    /// @notice The same legitimate partial fill FALSE-POSITIVES when the assertion is deployed with
    ///         an explicit `originalRouterFamily_ = false`, isolating the behavioural consequence of a
    ///         wrong family flag.
    /// @dev `_arm` uses the correct `true`; here we deploy with an explicit `false`. With the family
    ///      flag false the `_PARTIAL_FILL` skip short-circuits off, so the flat `>= minReturnAmount`
    ///      floor rejects a swap the router legitimately filled pro-rata. The assertion logic is
    ///      unchanged and correct.
    ///
    ///      NOTE: this is the *explicit-false* misconfiguration, NOT the mainnet backtest harness's
    ///      actual bug. The harness encoded a single-`address` constructor tail, which does not read
    ///      the missing bool as zero — it reverts construction outright
    ///      (`AssertionContractDeployFailed`). See
    ///      `testDeployment_OneArgPayload_RevertsDuringConstruction` for the real root cause; this
    ///      test only demonstrates what a *successfully deployed* wrong-family assertion would do.
    function testMinReturn_PartialFill_MisconfiguredFamilyFalse_Trips() public {
        uint256 spent = AMOUNT_IN / 2;
        uint256 fullMinimum = _expectedOut();

        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(dst);
        desc.srcReceivers = _one(address(pool));
        desc.srcAmounts = _one(spent);
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = recipient;
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = fullMinimum;
        desc.flags = PARTIAL_FILL;

        SwapExecutionParams memory p;
        p.callTarget = address(executor);
        p.targetData = _executorData(recipient);
        p.desc = desc;

        // Arm with originalRouterFamily_ = false (the backtest-harness misconfiguration).
        bytes memory createData = abi.encodePacked(
            type(KyberMetaAggregationRouterAssertion).creationCode, abi.encode(address(router), false)
        );
        cl.assertion(
            address(router), createData, KyberMetaAggregationRouterAssertion.assertReceiverGetsMinReturn.selector
        );

        vm.expectRevert(bytes("Kyber: dstReceiver credited below minReturnAmount"));
        router.swap(p);
    }

    /// @notice The REAL one-argument deployment payload `creationCode || abi.encode(address(router))`
    ///         REVERTS during construction — it does NOT silently zero the trailing bool.
    /// @dev This pins the actual root cause of the mainnet backtest trip. The harness built the
    ///      assertion create data with a single-arg `constructor(address)` ABI encoding (32 bytes of
    ///      constructor tail), but the assertion's constructor is the 2-arg
    ///      `constructor(address,bool)`. The compiler-generated constructor prologue ABI-decodes its
    ///      arguments from the code-appended tail and reverts when the tail is too short to contain
    ///      the `bool` — so construction aborts and `CREATE` returns `address(0)`. The trailing bool
    ///      never "reads as zero".
    ///
    ///      Under `pcl`/`cl.assertion` this same construction revert surfaces as
    ///      `AssertionContractDeployFailed` before the triggered `router.swap` ever runs (verified on
    ///      PCL 1.5.1 / Solc 0.8.30 by fredo, and reproduced here on PCL 1.6.0 / Solc 0.8.34). That
    ///      cheatcode path aborts the whole `pcl test` process rather than raising a catchable
    ///      Solidity revert, so this regression is pinned deterministically at the construction layer
    ///      via low-level `CREATE`: the exact one-argument payload fails, the correct two-argument
    ///      payload succeeds.
    function testDeployment_OneArgPayload_RevertsDuringConstruction() public {
        // The exact payload the backtest harness built: creation code + a single `address` arg.
        bytes memory oneArgPayload =
            abi.encodePacked(type(KyberMetaAggregationRouterAssertion).creationCode, abi.encode(address(router)));
        address oneArgDeployed;
        assembly {
            oneArgDeployed := create(0, add(oneArgPayload, 0x20), mload(oneArgPayload))
        }
        // Construction reverted: the too-short constructor tail cannot be decoded into (address,bool).
        assertEq(oneArgDeployed, address(0), "one-arg payload must fail construction, not zero the bool");

        // The correct two-argument payload constructs successfully.
        bytes memory twoArgPayload = abi.encodePacked(
            type(KyberMetaAggregationRouterAssertion).creationCode, abi.encode(address(router), true)
        );
        address twoArgDeployed;
        assembly {
            twoArgDeployed := create(0, add(twoArgPayload, 0x20), mload(twoArgPayload))
        }
        assertTrue(twoArgDeployed != address(0), "two-arg payload must construct");
    }

    /// @notice swapSimpleMode underpayment trips when the router guard is absent.
    function testMinReturn_SwapSimpleMode_Underpaid_Trips() public {
        router.setEnforceMinReturn(false);
        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(dst);
        desc.srcReceivers = _one(address(pool));
        desc.srcAmounts = _one(AMOUNT_IN);
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = recipient;
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = _expectedOut() + 100 ether;

        _armMinReturn();
        vm.expectRevert(bytes("Kyber: dstReceiver credited below minReturnAmount"));
        router.swapSimpleMode(address(executor), desc, _executorData(recipient), "");
    }

    // ===============================================================
    //  assertNoThirdPartyAllowanceDrain — approval safety
    // ===============================================================

    /// @notice A swap pulling only the initiator's approved funds is the expected path.
    function retiredAllowanceInference_HonestInitiatorPull_Passes() public {
        router.setEnforceMinReturn(false);
        SwapExecutionParams memory p = _arbitraryCallParams(address(0), "");
        p.desc.srcReceivers = _one(feeWallet);
        p.desc.srcAmounts = _one(25 ether);

        _armDrain();
        router.swap(p);
    }

    /// @notice A full honest swap (initiator pull, pool payout, fee leg) raises no false positive.
    function retiredAllowanceInference_HonestFullSwapNoFalsePositive_Passes() public {
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, _expectedOut());
        p.desc.feeReceivers = _one(feeWallet);
        p.desc.feeAmounts = _one(1 ether);

        _armDrain();
        router.swap(p);
        assertEq(src.balanceOf(feeWallet), 1 ether);
    }

    /// @notice An arbitrary call that spends a bystander's finite router approval is rejected.
    function retiredAllowanceInference_ArbitraryCallDrainsVictim_FiniteApproval_Trips() public {
        src.mint(victim, 1_000 ether);
        vm.prank(victim);
        src.approve(address(router), 100 ether);

        bytes memory drain = abi.encodeWithSelector(IERC20.transferFrom.selector, victim, attacker, 50 ether);
        SwapExecutionParams memory p = _arbitraryCallParams(address(src), drain);

        _armDrain();
        vm.expectRevert(bytes("Kyber: swap exercised third-party router allowance"));
        router.swap(p);
    }

    /// @notice A max (non-decrementing) approval drain is caught by the nonzero pre-call check.
    function retiredAllowanceInference_ArbitraryCallDrainsVictim_MaxApproval_Trips() public {
        src.mint(victim, 1_000 ether);
        vm.prank(victim);
        src.approve(address(router), type(uint256).max);

        bytes memory drain = abi.encodeWithSelector(IERC20.transferFrom.selector, victim, attacker, 50 ether);
        SwapExecutionParams memory p = _arbitraryCallParams(address(src), drain);

        _armDrain();
        vm.expectRevert(bytes("Kyber: swap exercised third-party router allowance"));
        router.swap(p);
    }

    /// @notice The router moving its own inventory is not a third-party drain.
    function retiredAllowanceInference_RouterSpendsOwnTokens_Passes() public {
        src.mint(address(router), 100 ether);
        bytes memory pay = abi.encodeWithSelector(IERC20.transfer.selector, attacker, 50 ether);
        SwapExecutionParams memory p = _arbitraryCallParams(address(src), pay);

        _armDrain();
        router.swap(p);
        assertEq(src.balanceOf(attacker), 50 ether);
    }

    /// @notice A third party paying out its own inventory (no router allowance) is not a drain.
    function retiredAllowanceInference_ThirdPartyPaysOwnTokensNoApproval_Passes() public {
        SelfFundedPayer payer = new SelfFundedPayer();
        dst.mint(address(payer), 100 ether);

        bytes memory pay = abi.encodeCall(SelfFundedPayer.payOut, (address(dst), recipient, 30 ether));
        SwapExecutionParams memory p = _arbitraryCallParams(address(payer), pay);

        _armDrain();
        router.swap(p);
        assertEq(dst.balanceOf(recipient), 30 ether);
    }

    /// @notice swapGeneric (raw-call entry point) drains a bystander's router approval — rejected.
    /// @dev On-chain `swapGeneric` raw-calls a whitelisted target with attacker-supplied calldata,
    ///      which is the most direct arbitrary-call drain surface. The invariant is path-independent,
    ///      so registering this entry point closes it the same way as `swap`.
    function retiredAllowanceInference_SwapGeneric_ArbitraryCallDrainsVictim_Trips() public {
        src.mint(victim, 1_000 ether);
        vm.prank(victim);
        src.approve(address(router), type(uint256).max);

        bytes memory drain = abi.encodeWithSelector(IERC20.transferFrom.selector, victim, attacker, 50 ether);
        SwapExecutionParams memory p = _arbitraryCallParams(address(src), drain);

        _armDrain();
        vm.expectRevert(bytes("Kyber: swap exercised third-party router allowance"));
        router.swapGeneric(p);
    }

    /// @notice An honest swapGeneric pulling only the initiator's funds raises no false positive.
    function retiredAllowanceInference_SwapGeneric_HonestPull_Passes() public {
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, _expectedOut());
        p.desc.feeReceivers = _one(feeWallet);
        p.desc.feeAmounts = _one(1 ether);

        _armDrain();
        router.swapGeneric(p);
        assertEq(src.balanceOf(feeWallet), 1 ether);
    }

    /// @notice swapSimpleMode honest pull raises no false positive.
    function retiredAllowanceInference_SwapSimpleMode_Honest_Passes() public {
        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(dst);
        desc.srcReceivers = _one(address(pool));
        desc.srcAmounts = _one(AMOUNT_IN);
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = recipient;
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = _expectedOut();

        _armDrain();
        router.swapSimpleMode(address(executor), desc, _executorData(recipient), "");
    }

    /// @notice A drain using an allowance the swap *creates mid-call* via permit is rejected.
    /// @dev The router runs `desc.permit` (attacker-supplied owner/spender) before any funds move,
    ///      so a bystander's signed EIP-2612 permit can mint `allowance(victim, router)` inside the
    ///      call. The victim held NO standing approval, so a pre-call allowance read sees zero; the
    ///      assertion still trips because it also flags the in-frame `Approval(victim, router)` the
    ///      permit emits — closing the permit-then-drain blind spot.
    function retiredAllowanceInference_PermitGrantedAllowanceDrain_Trips() public {
        PermitMintableToken permitToken = new PermitMintableToken("Permit", "PRM");
        permitToken.mint(victim, 1_000 ether);
        // Victim has NOT approved the router; the allowance is created inside the call via permit.
        assertEq(permitToken.allowance(victim, address(router)), 0);

        bytes memory permit = abi.encode(
            victim, address(router), uint256(50 ether), uint256(block.timestamp + 1), uint8(27), bytes32(0), bytes32(0)
        );
        assertEq(permit.length, 32 * 7);

        bytes memory drain = abi.encodeWithSelector(IERC20.transferFrom.selector, victim, attacker, 50 ether);
        SwapExecutionParams memory p = _arbitraryCallParams(address(permitToken), drain);
        p.desc.srcToken = address(permitToken);
        p.desc.permit = permit;

        _armDrain();
        vm.expectRevert(bytes("Kyber: swap exercised third-party router allowance"));
        router.swap(p);
    }

    /// @notice swapSimpleMode arbitrary-call drain is rejected just like the swap entry point.
    function retiredAllowanceInference_SwapSimpleMode_DrainViaArbitraryCall_Trips() public {
        router.setEnforceMinReturn(false);
        src.mint(victim, 1_000 ether);
        vm.prank(victim);
        src.approve(address(router), type(uint256).max);

        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(dst);
        desc.srcReceivers = _noAddrs();
        desc.srcAmounts = _noUints();
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = recipient;

        bytes memory drain = abi.encodeWithSelector(IERC20.transferFrom.selector, victim, attacker, 50 ether);

        _armDrain();
        vm.expectRevert(bytes("Kyber: swap exercised third-party router allowance"));
        router.swapSimpleMode(address(src), desc, drain, "");
    }
}
