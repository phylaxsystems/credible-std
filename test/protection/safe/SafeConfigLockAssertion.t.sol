// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {PhEvm} from "../../../src/PhEvm.sol";
import {SafeConfigLockAssertion} from "../../../src/protection/safe/SafeConfigLockAssertion.sol";

contract MockSafeConfigLockTarget {
    address internal constant SENTINEL_MODULES = address(0x1);

    bytes32 internal constant FALLBACK_HANDLER_STORAGE_SLOT =
        0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;
    bytes32 internal constant MODULE_GUARD_STORAGE_SLOT =
        0xb104e0b93118902c651344349b610029d694cfdec91c589c91ebafbcd0289947;

    uint256 internal threshold;
    address[] internal owners;
    address[] internal modules;

    constructor(
        address[] memory owners_,
        uint256 threshold_,
        address[] memory modules_,
        address guard_,
        address moduleGuard_,
        address fallbackHandler_
    ) {
        setOwners(owners_, threshold_);
        setModules(modules_);
        setGuard(guard_);
        setModuleGuard(moduleGuard_);
        setFallbackHandler(fallbackHandler_);
    }

    function getThreshold() external view returns (uint256) {
        return threshold;
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        virtual
        returns (address[] memory array, address next)
    {
        require(pageSize != 0, "MockSafe: page size zero");

        uint256 startIndex;
        if (start != SENTINEL_MODULES) {
            startIndex = type(uint256).max;
            for (uint256 i; i < modules.length; ++i) {
                if (modules[i] == start) {
                    startIndex = i + 1;
                    break;
                }
            }
            require(startIndex != type(uint256).max, "MockSafe: unsupported start");
        }

        uint256 remaining = modules.length - startIndex;
        uint256 count = remaining;
        if (count > pageSize) {
            count = pageSize;
            next = modules[startIndex + count - 1];
        } else {
            next = SENTINEL_MODULES;
        }

        array = new address[](count);
        for (uint256 i; i < count; ++i) {
            array[i] = modules[startIndex + i];
        }
    }

    function setThreshold(uint256 threshold_) public {
        threshold = threshold_;
    }

    function setOwners(address[] memory owners_, uint256 threshold_) public {
        delete owners;
        for (uint256 i; i < owners_.length; ++i) {
            owners.push(owners_[i]);
        }
        threshold = threshold_;
    }

    function setModules(address[] memory modules_) public {
        delete modules;
        for (uint256 i; i < modules_.length; ++i) {
            modules.push(modules_[i]);
        }
    }

    function setGuard(address guard_) public {
        _storeAddress(GUARD_STORAGE_SLOT, guard_);
    }

    function setModuleGuard(address moduleGuard_) public {
        _storeAddress(MODULE_GUARD_STORAGE_SLOT, moduleGuard_);
    }

    function setFallbackHandler(address fallbackHandler_) public {
        _storeAddress(FALLBACK_HANDLER_STORAGE_SLOT, fallbackHandler_);
    }

    function _storeAddress(bytes32 slot, address value) internal {
        assembly {
            sstore(slot, value)
        }
    }
}

/// @dev Models the linked-list traversal in Safe's ModuleManager, including the
///      different continuation values returned by 1.3.0 and 1.4.0+.
contract MockSafeLinkedListPaginationTarget is MockSafeConfigLockTarget {
    mapping(address => address) internal moduleLinks;
    bool internal immutable legacyPagination;

    constructor(address[] memory owners_, address[] memory modules_, bool legacyPagination_)
        MockSafeConfigLockTarget(owners_, 2, new address[](0), address(0), address(0), address(0))
    {
        legacyPagination = legacyPagination_;
        address previous = SENTINEL_MODULES;
        for (uint256 i; i < modules_.length; ++i) {
            moduleLinks[previous] = modules_[i];
            previous = modules_[i];
        }
        moduleLinks[previous] = SENTINEL_MODULES;
    }

    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        override
        returns (address[] memory array, address next)
    {
        if (!legacyPagination) {
            require(start == SENTINEL_MODULES || moduleLinks[start] != address(0), "GS105");
            require(pageSize > 0, "GS106");
        }
        array = new address[](pageSize);
        uint256 count;
        next = moduleLinks[start];
        while (next != address(0) && next != SENTINEL_MODULES && count < pageSize) {
            array[count++] = next;
            next = moduleLinks[next];
        }
        // Safe 1.3 returns the first omitted module; newer versions return the
        // last included module. Both start traversal at moduleLinks[start].
        if (!legacyPagination && next != SENTINEL_MODULES) {
            next = array[count - 1];
        }
        assembly {
            mstore(array, count)
        }
    }
}

/// @dev Supplies a fixed post-transaction snapshot for public-interface pagination
///      tests. Large module sets exceed the runtime's assertion gas budget, so
///      these tests check enumeration correctness, not production gas viability.
contract MockSafePaginationSnapshot {
    address internal immutable safe;

    constructor(address safe_) {
        safe = safe_;
    }

    function getAssertionAdopter() external view returns (address) {
        return safe;
    }

    function staticcallAt(address target, bytes calldata data, uint64 gasLimit, PhEvm.ForkId calldata fork)
        external
        view
        returns (PhEvm.StaticCallResult memory result)
    {
        require(target == safe && fork.forkType == 1 && fork.callIndex == 0, "unexpected snapshot");
        (result.ok, result.data) = target.staticcall{gas: gasLimit}(data);
    }

    function loadStateAt(address target, bytes32, PhEvm.ForkId calldata fork) external view returns (bytes32) {
        require(target == safe && fork.forkType == 1 && fork.callIndex == 0, "unexpected snapshot");
        // This fixture has no guard, module guard, or fallback handler.
        return bytes32(0);
    }
}

contract SafeConfigLockAssertionTest is Test, CredibleTest {
    address internal constant OWNER_A = address(0xA11CE);
    address internal constant OWNER_B = address(0xB0B);
    address internal constant OWNER_C = address(0xCA10);
    address internal constant OWNER_D = address(0xD00D);

    address internal constant MODULE_A = address(0xA001);
    address internal constant MODULE_B = address(0xB002);
    address internal constant MODULE_C = address(0xC003);

    address internal constant GUARD = address(0x1001);
    address internal constant MODULE_GUARD = address(0x1002);
    address internal constant FALLBACK_HANDLER = address(0x1003);
    address internal constant OTHER = address(0x9999);

    MockSafeConfigLockTarget internal safe;

    function setUp() public {
        safe = new MockSafeConfigLockTarget(
            _baselineOwners(), 2, _baselineModules(), GUARD, MODULE_GUARD, FALLBACK_HANDLER
        );
    }

    function testAllowsApprovedSafeConfiguration() public {
        _armBaselinePolicy();

        safe.setThreshold(3);
    }

    function testBlocksThresholdBelowMinimum() public {
        _armBaselinePolicy();

        vm.expectRevert(bytes("SafeConfigLock: threshold below minimum"));
        safe.setThreshold(1);
    }

    function testBlocksOwnerCountBelowMinimum() public {
        _armBaselinePolicy();

        address[] memory owners = new address[](2);
        owners[0] = OWNER_A;
        owners[1] = OWNER_B;

        vm.expectRevert(bytes("SafeConfigLock: owner count below minimum"));
        safe.setOwners(owners, 2);
    }

    function testBlocksUnapprovedOwnerSet() public {
        _armBaselinePolicy();

        address[] memory owners = new address[](3);
        owners[0] = OWNER_A;
        owners[1] = OWNER_B;
        owners[2] = OWNER_D;

        vm.expectRevert(bytes("SafeConfigLock: owner set not approved"));
        safe.setOwners(owners, 2);
    }

    function testAllowsDisabledModulesWithZeroSentinel() public {
        safe =
            new MockSafeConfigLockTarget(_baselineOwners(), 2, new address[](0), GUARD, MODULE_GUARD, FALLBACK_HANDLER);

        _armPolicy(
            _singleHash(_hashAddressSet(_baselineOwners())), _zeroHashList(), GUARD, MODULE_GUARD, FALLBACK_HANDLER
        );

        safe.setThreshold(3);
    }

    function testZeroModuleSentinelBlocksEnabledModule() public {
        safe =
            new MockSafeConfigLockTarget(_baselineOwners(), 2, new address[](0), GUARD, MODULE_GUARD, FALLBACK_HANDLER);
        _armPolicy(
            _singleHash(_hashAddressSet(_baselineOwners())), _zeroHashList(), GUARD, MODULE_GUARD, FALLBACK_HANDLER
        );

        address[] memory modules = new address[](1);
        modules[0] = MODULE_A;

        vm.expectRevert(bytes("SafeConfigLock: module set not approved"));
        safe.setModules(modules);
    }

    function testBlocksUnapprovedModuleSet() public {
        _armBaselinePolicy();

        address[] memory modules = new address[](2);
        modules[0] = MODULE_A;
        modules[1] = MODULE_C;

        vm.expectRevert(bytes("SafeConfigLock: module set not approved"));
        safe.setModules(modules);
    }

    function testAllowsApprovedLargerModuleSetWithinGasLimit() public {
        address[] memory modules = new address[](32);
        for (uint256 i; i < modules.length; ++i) {
            // forge-lint: disable-next-line(unsafe-typecast)
            modules[i] = address(uint160(0x10000 + i));
        }
        safe = new MockSafeConfigLockTarget(_baselineOwners(), 2, modules, GUARD, MODULE_GUARD, FALLBACK_HANDLER);

        _armPolicy(
            _singleHash(_hashAddressSet(_baselineOwners())),
            _singleHash(_hashAddressSet(modules)),
            GUARD,
            MODULE_GUARD,
            FALLBACK_HANDLER
        );

        safe.setThreshold(3);
    }

    function testPaginationSafe13Allows255Modules() public {
        _checkPagination(255, true, false);
    }

    function testPaginationSafe13Allows256Modules() public {
        _checkPagination(256, true, false);
    }

    function testPaginationSafe13Allows257Modules() public {
        _checkPagination(257, true, false);
    }

    function testPaginationSafe13Allows512Modules() public {
        _checkPagination(512, true, false);
    }

    function testPaginationSafe13Allows513Modules() public {
        _checkPagination(513, true, false);
    }

    function testPaginationSafe13Allows514Modules() public {
        _checkPagination(514, true, false);
    }

    function testPaginationSafe14PlusAllows255Modules() public {
        _checkPagination(255, false, false);
    }

    function testPaginationSafe14PlusAllows256Modules() public {
        _checkPagination(256, false, false);
    }

    function testPaginationSafe14PlusAllows257Modules() public {
        _checkPagination(257, false, false);
    }

    function testPaginationSafe14PlusAllows512Modules() public {
        _checkPagination(512, false, false);
    }

    function testPaginationSafe14PlusAllows513Modules() public {
        _checkPagination(513, false, false);
    }

    function testPaginationSafe14PlusAllows514Modules() public {
        _checkPagination(514, false, false);
    }

    function testPaginationSafe13RejectsMissingBoundaryHash257() public {
        _checkPagination(257, true, true);
    }

    function testPaginationSafe13RejectsMissingBoundaryHash514() public {
        _checkPagination(514, true, true);
    }

    function testPaginationSafe14PlusRejectsMissingBoundaryHash257() public {
        _checkPagination(257, false, true);
    }

    function testPaginationSafe14PlusRejectsMissingBoundaryHash514() public {
        _checkPagination(514, false, true);
    }

    function _checkPagination(uint256 count, bool legacyPagination, bool approveMissingBoundaries) internal {
        address[] memory modules = new address[](count);
        for (uint256 i; i < count; ++i) {
            // forge-lint: disable-next-line(unsafe-typecast)
            modules[i] = address(uint160(0x10000 + i));
        }
        safe = new MockSafeLinkedListPaginationTarget(_baselineOwners(), modules, legacyPagination);

        // Pin the fixture's version-specific cursor and the shared resume semantics.
        (address[] memory page, address next) = safe.getModulesPaginated(address(1), 256);
        assertEq(page.length, count < 256 ? count : 256);
        assertEq(next, count <= 256 ? address(1) : modules[legacyPagination ? 256 : 255]);
        if (count > 256) {
            (page,) = safe.getModulesPaginated(page[page.length - 1], 256);
            assertEq(page[0], modules[256]);
        }

        bytes32 approvedHash = _hashAddressSet(modules);
        if (approveMissingBoundaries) {
            // With the old cursor handling, Safe 1.3 skips indices 256 and 513:
            // each skipped module becomes the start argument for the next page.
            address[] memory incomplete = new address[](count - count / 257);
            uint256 included;
            for (uint256 i; i < count; ++i) {
                if ((i + 1) % 257 != 0) incomplete[included++] = modules[i];
            }
            bytes32 incompleteHash = _hashAddressSet(incomplete);
            assertTrue(approvedHash != incompleteHash);
            approvedHash = incompleteHash;
        }
        MockSafePaginationSnapshot snapshot = new MockSafePaginationSnapshot(address(safe));
        address phEvm = address(uint160(uint256(keccak256("Kim Jong Un Sucks"))));
        vm.etch(phEvm, address(snapshot).code);
        SafeConfigLockAssertion assertion = new SafeConfigLockAssertion(
            2,
            3,
            _singleHash(_hashAddressSet(_baselineOwners())),
            _singleHash(approvedHash),
            address(0),
            address(0),
            address(0)
        );

        if (approveMissingBoundaries) {
            vm.expectRevert(bytes("SafeConfigLock: module set not approved"));
        }
        assertion.assertSafeConfiguration();
    }

    function testBlocksGuardMismatch() public {
        _armBaselinePolicy();

        vm.expectRevert(bytes("SafeConfigLock: guard mismatch"));
        safe.setGuard(OTHER);
    }

    function testBlocksModuleGuardMismatch() public {
        _armBaselinePolicy();

        vm.expectRevert(bytes("SafeConfigLock: module guard mismatch"));
        safe.setModuleGuard(OTHER);
    }

    function testBlocksFallbackHandlerMismatch() public {
        _armBaselinePolicy();

        vm.expectRevert(bytes("SafeConfigLock: fallback handler mismatch"));
        safe.setFallbackHandler(OTHER);
    }

    function _armBaselinePolicy() internal {
        _armPolicy(
            _singleHash(_hashAddressSet(_baselineOwners())),
            _singleHash(_hashAddressSet(_baselineModules())),
            GUARD,
            MODULE_GUARD,
            FALLBACK_HANDLER
        );
    }

    function _armPolicy(
        bytes32[] memory ownerSetHashes,
        bytes32[] memory moduleSetHashes,
        address expectedGuard,
        address expectedModuleGuard,
        address expectedFallbackHandler
    ) internal {
        bytes memory createData = abi.encodePacked(
            type(SafeConfigLockAssertion).creationCode,
            abi.encode(
                2, 3, ownerSetHashes, moduleSetHashes, expectedGuard, expectedModuleGuard, expectedFallbackHandler
            )
        );

        cl.assertion(address(safe), createData, SafeConfigLockAssertion.assertSafeConfiguration.selector);
    }

    function _baselineOwners() internal pure returns (address[] memory owners) {
        owners = new address[](3);
        owners[0] = OWNER_A;
        owners[1] = OWNER_B;
        owners[2] = OWNER_C;
    }

    function _baselineModules() internal pure returns (address[] memory modules) {
        modules = new address[](2);
        modules[0] = MODULE_A;
        modules[1] = MODULE_B;
    }

    function _singleHash(bytes32 hash) internal pure returns (bytes32[] memory hashes) {
        hashes = new bytes32[](1);
        hashes[0] = hash;
    }

    function _zeroHashList() internal pure returns (bytes32[] memory hashes) {
        hashes = new bytes32[](1);
        hashes[0] = bytes32(0);
    }

    function _hashAddressSet(address[] memory accounts) internal pure returns (bytes32) {
        _sortAddresses(accounts);
        return keccak256(abi.encode(accounts));
    }

    function _sortAddresses(address[] memory accounts) internal pure {
        for (uint256 i = 1; i < accounts.length; ++i) {
            address current = accounts[i];
            uint256 j = i;

            while (j > 0 && uint160(accounts[j - 1]) > uint160(current)) {
                accounts[j] = accounts[j - 1];
                --j;
            }

            accounts[j] = current;
        }
    }
}
