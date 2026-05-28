// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
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

    function testAllowsApprovedModuleSetAcrossMultiplePages() public {
        address[] memory modules = new address[](257);
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
