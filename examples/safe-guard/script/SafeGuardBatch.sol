// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import {IERC165, ITransactionGuard} from "credible-std/protection/safe/CredibleSafeGuard.sol";

/// @notice Builds Safe Transaction Builder batches for installing and removing a Safe guard.
/// @dev The checksum implementation matches Safe Transaction Builder's canonical serializer for
///      the fixed one-transaction schema emitted by this contract.
abstract contract SafeGuardBatch is Script {
    enum Action {
        Install,
        Remove
    }

    bytes4 internal constant SAFE_GUARD_INTERFACE_ID = type(ITransactionGuard).interfaceId;
    string internal constant TX_BUILDER_VERSION = "2.0.1";

    error ZeroSafeAddress();
    error SafeHasNoCode(address safe);
    error ZeroGuardAddress();
    error GuardHasNoCode(address guard);
    error UnsupportedGuardInterface(address guard);
    error InvalidAction(string action);

    function buildInstallBatch(address safe, address guard, uint256 chainId, uint256 createdAt)
        public
        view
        returns (string memory)
    {
        _validateSafe(safe);
        _validateGuard(guard);
        return _buildBatch(safe, guard, Action.Install, chainId, createdAt);
    }

    function buildRemoveBatch(address safe, uint256 chainId, uint256 createdAt) public view returns (string memory) {
        _validateSafe(safe);
        return _buildBatch(safe, address(0), Action.Remove, chainId, createdAt);
    }

    function parseAction(string memory action) public pure returns (Action) {
        bytes32 actionHash = keccak256(bytes(action));
        if (actionHash == keccak256("install")) return Action.Install;
        if (actionHash == keccak256("remove")) return Action.Remove;
        revert InvalidAction(action);
    }

    function outputPath(Action action) public pure returns (string memory) {
        return action == Action.Install ? "safe-guard-output/install.json" : "safe-guard-output/remove.json";
    }

    function calculateChecksum(address safe, address guard, uint256 chainId, uint256 createdAt)
        public
        view
        returns (bytes32)
    {
        string memory safeString = vm.toString(safe);
        string memory guardString = vm.toString(guard);
        string memory chainIdString = vm.toString(chainId);
        string memory createdAtString = vm.toString(createdAt);

        string memory canonicalMeta = string.concat(
            '{["createdFromOwnerAddress","createdFromSafeAddress","description","name","txBuilderVersion"]',
            '"",',
            _quote(safeString),
            ',"",null,"',
            TX_BUILDER_VERSION,
            '",}'
        );

        string memory canonicalInput = string.concat('{["internalType","name","type"]', '"address","guard","address",}');
        string memory canonicalMethod =
            string.concat('{["inputs","name","payable"]', "[", canonicalInput, "]", ',"setGuard",false,}');
        string memory canonicalInputs = string.concat('{["guard"]', _quote(guardString), ",}");
        string memory canonicalTransaction = string.concat(
            '{["contractInputsValues","contractMethod","data","to","value"]',
            canonicalInputs,
            ",",
            canonicalMethod,
            ",null,",
            _quote(safeString),
            ',"0",}'
        );
        string memory canonicalRoot = string.concat(
            '{["chainId","createdAt","meta","transactions","version"]',
            _quote(chainIdString),
            ",",
            createdAtString,
            ",",
            canonicalMeta,
            ",[",
            canonicalTransaction,
            '],"1.0",}'
        );

        return keccak256(bytes(canonicalRoot));
    }

    function _buildBatch(address safe, address guard, Action action, uint256 chainId, uint256 createdAt)
        internal
        view
        returns (string memory)
    {
        string memory safeString = vm.toString(safe);
        string memory guardString = vm.toString(guard);
        string memory checksum = vm.toString(calculateChecksum(safe, guard, chainId, createdAt));
        string memory name = action == Action.Install ? "Install Credible Safe Guard" : "Remove Credible Safe Guard";

        return string.concat(
            '{"version":"1.0","chainId":',
            _quote(vm.toString(chainId)),
            ',"createdAt":',
            vm.toString(createdAt),
            ',"meta":{"name":',
            _quote(name),
            ',"description":"","txBuilderVersion":"',
            TX_BUILDER_VERSION,
            '","createdFromSafeAddress":',
            _quote(safeString),
            ',"createdFromOwnerAddress":"","checksum":',
            _quote(checksum),
            '},"transactions":[{"to":',
            _quote(safeString),
            ',"value":"0","data":null,"contractMethod":{"inputs":[{"internalType":"address","name":"guard","type":"address"}],"name":"setGuard","payable":false},"contractInputsValues":{"guard":',
            _quote(guardString),
            "}}]}"
        );
    }

    function _validateSafe(address safe) internal view {
        if (safe == address(0)) revert ZeroSafeAddress();
        if (safe.code.length == 0) revert SafeHasNoCode(safe);
    }

    function _validateGuard(address guard) internal view {
        if (guard == address(0)) revert ZeroGuardAddress();
        if (guard.code.length == 0) revert GuardHasNoCode(guard);

        (bool success, bytes memory result) =
            guard.staticcall(abi.encodeCall(IERC165.supportsInterface, (SAFE_GUARD_INTERFACE_ID)));
        uint256 supported;
        if (success && result.length == 32) {
            assembly ("memory-safe") {
                supported := mload(add(result, 0x20))
            }
        }
        if (!success || result.length != 32 || supported != 1) revert UnsupportedGuardInterface(guard);
    }

    function _quote(string memory value) internal pure returns (string memory) {
        return string.concat('"', value, '"');
    }
}
