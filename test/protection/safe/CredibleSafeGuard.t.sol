// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {ICredibleRegistry} from "../../../src/protection/safe/ICredibleRegistry.sol";
import {CredibleSafeGuard, Enum, IERC165, ITransactionGuard} from "../../../src/protection/safe/CredibleSafeGuard.sol";
import {InitialProtocolManager} from "../../../src/protection/initial_protocol_manager/InitialProtocolManager.sol";
import {IInitialProtocolManager} from "../../../src/protection/initial_protocol_manager/IInitialProtocolManager.sol";

/// @notice Test double for the Credible Registry. Exposes fine-grained setters and a faithful
///         `markCurrentBlockCredible()` replicating `phylaxsystems/credible-registry` semantics.
contract MockCredibleRegistry is ICredibleRegistry {
    mapping(uint256 blockNumber => bool credible) internal _credible;
    uint256 internal _lastCredibleBlock;

    function setCredibleBlock(uint256 blockNumber, bool credible) external {
        _credible[blockNumber] = credible;
    }

    function setLastCredibleBlock(uint256 blockNumber) external {
        _lastCredibleBlock = blockNumber;
    }

    /// @dev Mirrors the real registry: marks `block.number` credible and advances the pointer.
    function markCurrentBlockCredible() external {
        _credible[block.number] = true;
        _lastCredibleBlock = block.number;
    }

    function isCredibleBlock(uint256 blockNumber) external view returns (bool) {
        return _credible[blockNumber];
    }

    function lastCredibleBlock() external view returns (uint256) {
        return _lastCredibleBlock;
    }
}

/// @notice Minimal Safe stand-in that calls the guard before "executing", mimicking the
///         relevant slice of `Safe.execTransaction`.
contract MockSafe {
    CredibleSafeGuard public immutable guard;
    uint256 public executed;

    constructor(CredibleSafeGuard guard_) {
        guard = guard_;
    }

    function execTransaction(address to, uint256 value, bytes memory data, Enum.Operation operation) external {
        guard.checkTransaction(to, value, data, operation, 0, 0, 0, address(0), payable(address(0)), "", msg.sender);
        executed++;
    }
}

contract CredibleSafeGuardTest is Test {
    /// @dev Known Safe `type(Guard).interfaceId` / `type(ITransactionGuard).interfaceId`.
    bytes4 internal constant SAFE_GUARD_INTERFACE_ID = 0xe6d7a83a;
    bytes4 internal constant ERC165_INTERFACE_ID = 0x01ffc9a7;

    /// @dev ~15 minutes of 12s blocks; chosen so boundaries are easy to reason about.
    uint256 internal constant THRESHOLD = 75;
    uint256 internal constant BASE_BLOCK = 1_000_000;
    address internal constant PROTOCOL_MANAGER = address(0xA11CE);

    MockCredibleRegistry internal registry;
    CredibleSafeGuard internal guard;

    function setUp() public {
        registry = new MockCredibleRegistry();
        guard = new CredibleSafeGuard(registry, THRESHOLD, PROTOCOL_MANAGER);
        vm.roll(BASE_BLOCK);
    }

    /// @dev Calls the guard with a representative full Safe transaction tuple.
    function _check() internal view {
        _checkGuard(guard);
    }

    function _checkGuard(CredibleSafeGuard guard_) internal view {
        guard_.checkTransaction(
            address(0xBEEF),
            1 ether,
            hex"abcdef",
            Enum.Operation.Call,
            21_000,
            0,
            0,
            address(0),
            payable(address(0)),
            hex"1234",
            address(0xCAFE)
        );
    }

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    function test_constructor_storesArgs() public view {
        assertEq(address(guard.credibleRegistry()), address(registry));
        assertEq(guard.failOpenBlockThreshold(), THRESHOLD);
        assertEq(guard.initialProtocolManager(), PROTOCOL_MANAGER);
    }

    function test_constructor_revertsOnZeroRegistry() public {
        vm.expectRevert(CredibleSafeGuard.ZeroCredibleRegistryAddress.selector);
        new CredibleSafeGuard(ICredibleRegistry(address(0)), THRESHOLD, PROTOCOL_MANAGER);
    }

    function test_constructor_revertsOnZeroThreshold() public {
        vm.expectRevert(CredibleSafeGuard.ZeroFailOpenBlockThreshold.selector);
        new CredibleSafeGuard(registry, 0, PROTOCOL_MANAGER);
    }

    function test_constructor_revertsOnZeroProtocolManager() public {
        vm.expectRevert(InitialProtocolManager.ZeroInitialProtocolManager.selector);
        new CredibleSafeGuard(registry, THRESHOLD, address(0));
    }

    /// @dev The state oracle reads the manager through {IInitialProtocolManager}; confirm the guard
    ///      satisfies that interface's getter when called through the interface type.
    function test_conformsToInitialProtocolManagerInterface() public view {
        IInitialProtocolManager asInterface = IInitialProtocolManager(address(guard));
        assertEq(asInterface.initialProtocolManager(), PROTOCOL_MANAGER);
    }

    // ---------------------------------------------------------------------
    // ERC-165 / Safe drop-in compatibility
    // ---------------------------------------------------------------------

    function test_supportsInterface_safeGuardAndErc165() public view {
        assertTrue(guard.supportsInterface(SAFE_GUARD_INTERFACE_ID));
        assertTrue(guard.supportsInterface(type(ITransactionGuard).interfaceId));
        assertTrue(guard.supportsInterface(ERC165_INTERFACE_ID));
        assertTrue(guard.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_computedIdMatchesSafeConstant() public pure {
        assertEq(type(ITransactionGuard).interfaceId, SAFE_GUARD_INTERFACE_ID);
    }

    function test_supportsInterface_rejectsOthers() public view {
        // EIP-165 mandates returning false for 0xffffffff.
        assertFalse(guard.supportsInterface(0xffffffff));
        assertFalse(guard.supportsInterface(0xdeadbeef));
        assertFalse(guard.supportsInterface(0x00000000));
    }

    // ---------------------------------------------------------------------
    // Allow path: current block is credible
    // ---------------------------------------------------------------------

    function test_allows_whenCurrentBlockCredible() public {
        registry.markCurrentBlockCredible();

        _check();
        assertTrue(guard.isCurrentBlockAllowed());
        assertFalse(guard.failOpenActive());
    }

    function test_allows_whenCurrentBlockCredible_beatsHugeGapInRegistryPointer() public {
        // Even if lastCredibleBlock happens to equal current block, gap is 0 -> not fail open,
        // and credibility carries the allow.
        registry.markCurrentBlockCredible();
        assertEq(registry.lastCredibleBlock(), block.number);
        _check();
    }

    // ---------------------------------------------------------------------
    // Block path: builder set live, current block not credible
    // ---------------------------------------------------------------------

    function test_reverts_whenNotCredible_withinThreshold() public {
        // Last credible block is 10 behind (<= 75) -> builder set still considered live.
        registry.setLastCredibleBlock(block.number - 10);

        assertFalse(guard.isCurrentBlockAllowed());
        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        _check();
    }

    function test_reverts_atFailOpenBoundary() public {
        // gap == threshold (75) is NOT strictly greater -> still live -> must be credible.
        registry.setLastCredibleBlock(block.number - THRESHOLD);

        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        _check();
    }

    // ---------------------------------------------------------------------
    // Fail-open path: builder set offline
    // ---------------------------------------------------------------------

    function test_failsOpen_whenGapExceedsThreshold() public {
        // gap == threshold + 1 (76) -> fail open even though current block is not credible.
        registry.setLastCredibleBlock(block.number - (THRESHOLD + 1));

        assertTrue(guard.failOpenActive());
        assertTrue(guard.isCurrentBlockAllowed());
        _check();
    }

    function test_failsOpen_whenRegistryNeverMarked_andBeyondThreshold() public {
        // lastCredibleBlock defaults to 0; once current block exceeds the threshold, fail open.
        vm.roll(THRESHOLD + 1);
        assertTrue(guard.failOpenActive());
        _check();
    }

    function test_reverts_whenRegistryNeverMarked_atThresholdBlock() public {
        // At exactly the threshold block, gap (== block.number) is not strictly greater.
        vm.roll(THRESHOLD);
        assertFalse(guard.failOpenActive());
        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        _check();
    }

    function test_checksCurrentBlockOnly_notPreviousCredibleBlock() public {
        // Mark block N credible, then advance one block: N+1 is not credible and still within
        // the live window, so the guard blocks.
        registry.markCurrentBlockCredible();
        vm.roll(block.number + 1);

        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        _check();
    }

    // ---------------------------------------------------------------------
    // Fail-open path: registry unavailable or malformed
    // ---------------------------------------------------------------------

    function test_failsOpen_whenCredibilityReadReverts() public {
        vm.mockCallRevert(
            address(registry), abi.encodeCall(ICredibleRegistry.isCredibleBlock, (block.number)), "registry unavailable"
        );

        assertTrue(guard.isCurrentBlockAllowed());
        assertTrue(guard.failOpenActive());
        _check();
    }

    function test_failsOpen_whenCredibilityReadReturnsShortData() public {
        vm.mockCall(
            address(registry),
            abi.encodeCall(ICredibleRegistry.isCredibleBlock, (block.number)),
            abi.encodePacked(uint8(1))
        );

        assertTrue(guard.isCurrentBlockAllowed());
        _check();
    }

    function test_failsOpen_whenCredibilityReadReturnsNonCanonicalBool() public {
        vm.mockCall(
            address(registry), abi.encodeCall(ICredibleRegistry.isCredibleBlock, (block.number)), abi.encode(uint256(2))
        );

        assertTrue(guard.isCurrentBlockAllowed());
        _check();
    }

    function test_failsOpen_whenLastCredibleBlockReadReverts() public {
        registry.setCredibleBlock(block.number, false);
        vm.mockCallRevert(
            address(registry), abi.encodeCall(ICredibleRegistry.lastCredibleBlock, ()), "registry unavailable"
        );

        assertTrue(guard.failOpenActive());
        assertTrue(guard.isCurrentBlockAllowed());
        _check();
    }

    function test_failsOpen_whenRegistryHasNoCode() public {
        CredibleSafeGuard codelessRegistryGuard =
            new CredibleSafeGuard(ICredibleRegistry(address(0xBEEF)), THRESHOLD, PROTOCOL_MANAGER);

        assertTrue(codelessRegistryGuard.isCurrentBlockAllowed());
        _checkGuard(codelessRegistryGuard);
    }

    function test_credibleHotPath_doesNotRequireLastBlockRead() public {
        registry.markCurrentBlockCredible();
        vm.mockCallRevert(
            address(registry), abi.encodeCall(ICredibleRegistry.lastCredibleBlock, ()), "registry unavailable"
        );

        _check();
    }

    // ---------------------------------------------------------------------
    // Defensive: registry reports a last credible block at/after current block
    // ---------------------------------------------------------------------

    function test_noUnderflow_whenLastCredibleBlockInFuture() public {
        registry.setLastCredibleBlock(block.number + 5);
        // Not fail open, current block not credible -> clean NonCredibleBlock revert, no panic.
        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        _check();
    }

    // ---------------------------------------------------------------------
    // Post-execution hook is a no-op
    // ---------------------------------------------------------------------

    function test_checkAfterExecution_isNoop() public view {
        guard.checkAfterExecution(bytes32(0), true);
        guard.checkAfterExecution(keccak256("tx"), false);
    }

    // ---------------------------------------------------------------------
    // Full ABI exercise, including delegatecall operation
    // ---------------------------------------------------------------------

    function test_checkTransaction_delegateCallOperation_allowedWhenCredible() public {
        registry.markCurrentBlockCredible();
        guard.checkTransaction(
            address(0x1234),
            0,
            hex"deadbeef",
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(this)
        );
    }

    function test_checkTransaction_delegateCallOperation_blockedWhenNotCredible() public {
        registry.setLastCredibleBlock(block.number - 1);
        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        guard.checkTransaction(
            address(0x1234),
            0,
            hex"deadbeef",
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(this)
        );
    }

    // ---------------------------------------------------------------------
    // Integration via a mock Safe
    // ---------------------------------------------------------------------

    function test_integration_safeExecution_allowedInCredibleBlock() public {
        MockSafe safe = new MockSafe(guard);
        registry.markCurrentBlockCredible();

        safe.execTransaction(address(0xABCD), 0, hex"00", Enum.Operation.Call);
        assertEq(safe.executed(), 1);
    }

    function test_integration_safeExecution_blockedInNonCredibleBlock() public {
        MockSafe safe = new MockSafe(guard);
        registry.setLastCredibleBlock(block.number - 1);

        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        safe.execTransaction(address(0xABCD), 0, hex"00", Enum.Operation.Call);
        assertEq(safe.executed(), 0);
    }

    function test_integration_safeExecution_failsOpenWhenBuilderOffline() public {
        MockSafe safe = new MockSafe(guard);
        registry.setLastCredibleBlock(block.number - (THRESHOLD + 1));

        safe.execTransaction(address(0xABCD), 0, hex"00", Enum.Operation.Call);
        assertEq(safe.executed(), 1);
    }

    function test_integration_endToEnd_builderStallThenRecover() public {
        MockSafe safe = new MockSafe(guard);

        // Builder healthy: this block is credible -> allowed.
        registry.markCurrentBlockCredible();
        safe.execTransaction(address(0xABCD), 0, "", Enum.Operation.Call);

        // Builder misses a few blocks but is still within the live window -> blocked.
        vm.roll(block.number + 10);
        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        safe.execTransaction(address(0xABCD), 0, "", Enum.Operation.Call);

        // Builder stays silent past the window -> fail open -> allowed.
        vm.roll(block.number + THRESHOLD);
        safe.execTransaction(address(0xABCD), 0, "", Enum.Operation.Call);

        // Builder recovers and marks the new current block -> allowed again.
        registry.markCurrentBlockCredible();
        safe.execTransaction(address(0xABCD), 0, "", Enum.Operation.Call);

        assertEq(safe.executed(), 3);
    }

    // ---------------------------------------------------------------------
    // Fuzz: decision is exactly "credible current block OR gap beyond threshold"
    // ---------------------------------------------------------------------

    function testFuzz_decisionMatchesSpec(uint256 gap, bool currentCredible) public {
        gap = bound(gap, 0, 10 * THRESHOLD);
        // Keep BASE_BLOCK large enough that block.number - gap never underflows.
        registry.setLastCredibleBlock(block.number - gap);
        if (currentCredible) registry.setCredibleBlock(block.number, true);

        bool failOpen = gap > THRESHOLD; // block.number > last is guaranteed for gap > 0
        bool expectedAllowed = failOpen || currentCredible;

        assertEq(guard.failOpenActive(), failOpen);
        assertEq(guard.isCurrentBlockAllowed(), expectedAllowed);

        if (expectedAllowed) {
            _check();
        } else {
            vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
            _check();
        }
    }
}
