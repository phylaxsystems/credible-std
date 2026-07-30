// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {
    KyberMetaAggregationRouterAssertionBase,
    KyberModernMetaAggregationRouterAssertion,
    KyberOriginalMetaAggregationRouterAssertion
} from "../src/KyberMetaAggregationRouterAssertion.sol";
import {
    IKyberMetaAggregationRouterV2Like,
    SimpleSwapData,
    SwapDescriptionV2,
    SwapExecutionParams
} from "../src/KyberMetaAggregationRouterInterfaces.sol";
import {
    FeeOnTransferToken,
    MintableToken,
    MockAggregationExecutor,
    MockKyberRouterV2,
    MockSameTokenExecutor,
    MockUniV2Pool,
    PermitMintableToken,
    SelfFundedPayer
} from "./KyberSwapMocks.sol";

/// @notice Focused behavior tests for the KyberSwap router assertions.
/// @dev The executable semantic suite reproduces the verified `swap` dispatch, receiver-delta,
///      same-token snapshot, claim/approve separation, and simple-mode partial-fill boundaries.
contract KyberMetaAggregationRouterAssertionTest is Test, CredibleTest {
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
            type(KyberOriginalMetaAggregationRouterAssertion).creationCode, abi.encode(address(router))
        );
        cl.assertion(address(router), createData, fnSelector);
    }

    function _armDrain() internal {
        _arm(KyberMetaAggregationRouterAssertionBase.assertNoThirdPartyAllowanceDrain.selector);
    }

    function _armMinReturn() internal {
        _arm(KyberMetaAggregationRouterAssertionBase.assertReceiverGetsMinReturn.selector);
    }

    function _armModernMinReturn() internal {
        bytes memory createData =
            abi.encodePacked(type(KyberModernMetaAggregationRouterAssertion).creationCode, abi.encode(address(router)));
        cl.assertion(
            address(router), createData, KyberMetaAggregationRouterAssertionBase.assertReceiverGetsMinReturn.selector
        );
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
        return abi.encode(address(pool), address(src), to);
    }

    function _genericExecutorData(address to) internal view returns (bytes memory) {
        return abi.encodeCall(MockAggregationExecutor.callBytes, (_executorData(to)));
    }

    function _simpleExecutorData(address to, uint256 amount) internal view returns (bytes memory) {
        SimpleSwapData memory data;
        data.firstPools = _one(address(pool));
        data.firstSwapAmounts = _one(amount);
        data.swapDatas = new bytes[](1);
        data.swapDatas[0] = _executorData(to);
        data.deadline = block.timestamp;
        return abi.encode(data);
    }

    function _expectedOut() internal view returns (uint256) {
        return pool.getAmountOut(AMOUNT_IN, pool.reserve0(), pool.reserve1());
    }

    function _expectedOutFor(uint256 amountIn) internal view returns (uint256) {
        return pool.getAmountOut(amountIn, pool.reserve0(), pool.reserve1());
    }

    uint256 internal constant PARTIAL_FILL = 0x01;
    uint256 internal constant SHOULD_CLAIM = 0x04;
    uint256 internal constant SIMPLE_SWAP = 0x20;
    uint256 internal constant APPROVE_FUND = 0x100;

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

    /// @notice The verified router's own balance-delta guard rejects fee-on-transfer underpayment.
    function testRouter_FeeOnTransferDstToken_RevertsBeforeAssertion() public {
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
        p.targetData = abi.encode(address(fotPool), address(src), recipient);
        p.desc = desc;

        vm.expectRevert(bytes("Return amount is not enough"));
        router.swap(p);
    }

    /// @notice A full-fill `swapSimpleMode` route delivers at least the signed minimum.
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
        router.swapSimpleMode(address(executor), desc, _simpleExecutorData(recipient, AMOUNT_IN), "");
    }

    /// @notice swapGeneric honest path delivers at least the signed minimum.
    function testMinReturn_SwapGeneric_Honest_Passes() public {
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, _expectedOut());
        p.targetData = _genericExecutorData(recipient);

        _armMinReturn();
        router.swapGeneric(p);
        assertGe(dst.balanceOf(recipient), _expectedOut());
    }

    /// @notice swapGeneric underpayment trips when the router guard is absent.
    function testMinReturn_SwapGeneric_Underpaid_Trips() public {
        router.setEnforceMinReturn(false);
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, _expectedOut() + 100 ether);
        p.targetData = _genericExecutorData(recipient);

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

    /// @notice A genuine `swapGeneric` claim-mode partial fill can credit less than the flat minimum.
    /// @dev `_SHOULD_CLAIM` makes `swapGeneric` collect the full amount and then recompute/refund
    ///      the unspent portion, so its pro-rated minimum is load-bearing.
    function testMinReturn_SwapGenericClaimPartialFill_NoFalsePositive_Passes() public {
        uint256 spent = AMOUNT_IN / 2;
        uint256 fullMinimum = _expectedOut(); // signed minimum for the full order size

        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(dst);
        desc.srcReceivers = _noAddrs();
        desc.srcAmounts = _noUints();
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = recipient;
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = fullMinimum;
        desc.flags = PARTIAL_FILL | SHOULD_CLAIM | APPROVE_FUND;

        SwapExecutionParams memory p;
        p.callTarget = address(executor);
        p.approveTarget = address(executor);
        p.targetData = abi.encodeCall(
            MockAggregationExecutor.callBytes, (abi.encode(address(pool), address(src), recipient, spent))
        );
        p.desc = desc;

        _armMinReturn();
        router.swapGeneric(p); // router's pro-rated guard passes; assertion must not false-positive
        // The recipient is genuinely credited below the flat minimum — proving the skip is load-bearing.
        assertLt(dst.balanceOf(recipient), fullMinimum);
    }

    /// @notice Direct simple mode measures partial spend from the caller's source-balance delta.
    function testMinReturn_SwapSimpleMode_PartialFill_NoFalsePositive_Passes() public {
        uint256 spent = AMOUNT_IN / 2;
        uint256 fullMinimum = _expectedOut();

        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(dst);
        desc.srcReceivers = _noAddrs();
        desc.srcAmounts = _noUints();
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = recipient;
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = fullMinimum;
        desc.flags = PARTIAL_FILL;

        _armMinReturn();
        router.swapSimpleMode(address(executor), desc, _simpleExecutorData(recipient, spent), "");
        assertLt(dst.balanceOf(recipient), fullMinimum);
    }

    /// @notice `swap + SIMPLE_SWAP` delegates to the same caller-balance accounting path.
    function testMinReturn_SwapDelegatedSimpleMode_PartialFill_NoFalsePositive_Passes() public {
        uint256 spent = AMOUNT_IN / 2;
        uint256 fullMinimum = _expectedOut();

        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(dst);
        desc.srcReceivers = _noAddrs();
        desc.srcAmounts = _noUints();
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = recipient;
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = fullMinimum;
        desc.flags = PARTIAL_FILL | SIMPLE_SWAP;

        SwapExecutionParams memory p;
        p.callTarget = address(executor);
        p.targetData = _simpleExecutorData(recipient, spent);
        p.desc = desc;

        _armMinReturn();
        router.swap(p);
        assertLt(dst.balanceOf(recipient), fullMinimum);
    }

    /// @notice Bit zero alone cannot bypass the original-family flat minimum.
    /// @dev For ordinary ERC20 input without `_SHOULD_CLAIM`, the verified router keeps
    ///      `spentAmount == desc.amount`; its pro-rated equation therefore equals the flat floor.
    function testMinReturn_PartialBitWithoutClaim_Underpaid_Trips() public {
        router.setEnforceMinReturn(false);
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, _expectedOut() + 100 ether);
        p.desc.flags = PARTIAL_FILL;

        _armMinReturn();
        vm.expectRevert(bytes("Kyber: dstReceiver credited below minReturnAmount"));
        router.swap(p);
    }

    /// @notice Claim/approve bits do not move ordinary `swap` into pro-rated accounting.
    /// @dev The verified entry point ignores these `swapGeneric`-only flags outside simple mode.
    function testMinReturn_SwapClaimFlagsDoNotBypassFlatMinimum_Trips() public {
        router.setEnforceMinReturn(false);
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, _expectedOut() + 100 ether);
        p.approveTarget = address(executor);
        p.desc.flags = PARTIAL_FILL | SHOULD_CLAIM | APPROVE_FUND;

        _armMinReturn();
        vm.expectRevert(bytes("Kyber: dstReceiver credited below minReturnAmount"));
        router.swap(p);
    }

    /// @notice Caller-controlled bit zero cannot bypass the modern-family artifact.
    function testMinReturn_ModernFamily_PartialBitUnderpaid_Trips() public {
        router.setEnforceMinReturn(false);
        SwapExecutionParams memory p = _honestParams(address(dst), recipient, _expectedOut() + 100 ether);
        p.desc.flags = PARTIAL_FILL;

        _armModernMinReturn();
        vm.expectRevert(bytes("Kyber: dstReceiver credited below minReturnAmount"));
        router.swap(p);
    }

    /// @notice Same-token routes are outside the outer-call additive balance window.
    function testMinReturn_SameToken_RouterValidRouteIsSkipped() public {
        MockSameTokenExecutor sameTokenExecutor = new MockSameTokenExecutor();
        src.mint(address(sameTokenExecutor), AMOUNT_IN);

        SwapDescriptionV2 memory desc;
        desc.srcToken = address(src);
        desc.dstToken = address(src);
        desc.srcReceivers = _one(address(pool));
        desc.srcAmounts = _one(AMOUNT_IN);
        desc.feeReceivers = _noAddrs();
        desc.feeAmounts = _noUints();
        desc.dstReceiver = address(this);
        desc.amount = AMOUNT_IN;
        desc.minReturnAmount = AMOUNT_IN;

        SwapExecutionParams memory p;
        p.callTarget = address(sameTokenExecutor);
        p.targetData = abi.encode(address(src), address(this), AMOUNT_IN);
        p.desc = desc;

        _armMinReturn();
        router.swap(p);
        assertEq(src.balanceOf(address(this)), 1_000 ether);
    }

    /// @notice Router-family selection is encoded in separate one-argument artifacts.
    function testDeployment_FamilyArtifactsHaveNoBooleanConfiguration() public {
        KyberOriginalMetaAggregationRouterAssertion original =
            new KyberOriginalMetaAggregationRouterAssertion(address(router));
        KyberModernMetaAggregationRouterAssertion modern =
            new KyberModernMetaAggregationRouterAssertion(address(router));

        assertTrue(address(original) != address(0));
        assertTrue(address(modern) != address(0));
    }

    /// @notice The original artifact registers the verified `swapGeneric` surface.
    function testTriggers_OriginalFamilyRegistersSwapGeneric() public {
        KyberOriginalMetaAggregationRouterAssertion original =
            new KyberOriginalMetaAggregationRouterAssertion(address(router));
        bytes4[] memory selectors = original.protectedSelectors();

        assertEq(selectors.length, 3);
        assertEq(selectors[0], IKyberMetaAggregationRouterV2Like.swap.selector);
        assertEq(selectors[1], IKyberMetaAggregationRouterV2Like.swapGeneric.selector);
        assertEq(selectors[2], IKyberMetaAggregationRouterV2Like.swapSimpleMode.selector);
    }

    /// @notice The modern artifact cannot accidentally register the absent `swapGeneric` surface.
    function testTriggers_ModernFamilyOmitsSwapGeneric() public {
        KyberModernMetaAggregationRouterAssertion modern =
            new KyberModernMetaAggregationRouterAssertion(address(router));
        bytes4[] memory selectors = modern.protectedSelectors();

        assertEq(selectors.length, 2);
        assertEq(selectors[0], IKyberMetaAggregationRouterV2Like.swap.selector);
        assertEq(selectors[1], IKyberMetaAggregationRouterV2Like.swapSimpleMode.selector);
    }

    /// @notice A compromised simple-mode runtime that omits its guard still cannot underpay.
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
        router.swapSimpleMode(address(executor), desc, _simpleExecutorData(recipient, AMOUNT_IN), "");
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
        router.swapSimpleMode(address(executor), desc, _simpleExecutorData(recipient, AMOUNT_IN), "");
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
}
