// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {Safe} from "../../../lib/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "../../../lib/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Enum} from "../../../lib/safe-smart-account/contracts/common/Enum.sol";

import {CredibleSafeGuard} from "credible-std/protection/safe/CredibleSafeGuard.sol";
import {CredibleRegistryMock} from "../src/CredibleRegistryMock.sol";
import {DeployCredibleSafeGuard} from "../script/DeployCredibleSafeGuard.s.sol";
import {GenerateSafeGuardBatch} from "../script/GenerateSafeGuardBatch.s.sol";
import {SafeGuardBatch} from "../script/SafeGuardBatch.sol";

contract UnsupportedGuard {}

contract CredibleSafeGuardScriptsTest is Test {
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;
    bytes32 internal constant REFERENCE_CHECKSUM = 0x8994ee462d748c24ecd7804083007dd231e36ff84da4b272921c30d1ae7f0df0;

    uint256 internal constant THRESHOLD = 75;
    uint256 internal constant CREATED_AT = 1_700_000_000_000;

    uint256 internal ownerPk = uint256(keccak256("safe.owner"));
    address internal owner;

    CredibleRegistryMock internal registry;
    Safe internal safe;
    GenerateSafeGuardBatch internal generator;
    DeployCredibleSafeGuard internal deployer;

    function setUp() public {
        owner = vm.addr(ownerPk);
        registry = new CredibleRegistryMock();
        generator = new GenerateSafeGuardBatch();
        deployer = new DeployCredibleSafeGuard();

        Safe singleton = new Safe();
        SafeProxyFactory factory = new SafeProxyFactory();
        address[] memory owners = new address[](1);
        owners[0] = owner;
        bytes memory initializer =
            abi.encodeCall(Safe.setup, (owners, 1, address(0), "", address(0), address(0), 0, payable(address(0))));
        safe = Safe(payable(address(factory.createProxyWithNonce(address(singleton), initializer, 0))));

        vm.roll(1_000_000);
    }

    function test_deployHelper_deploysConfiguredGuard() public {
        CredibleSafeGuard guard = deployer.deploy(address(registry), THRESHOLD);

        assertEq(address(guard.credibleRegistry()), address(registry));
        assertEq(guard.failOpenBlockThreshold(), THRESHOLD);
    }

    function test_deployHelper_preservesConstructorValidation() public {
        vm.expectRevert(CredibleSafeGuard.ZeroCredibleRegistryAddress.selector);
        deployer.deploy(address(0), THRESHOLD);

        vm.expectRevert(CredibleSafeGuard.ZeroFailOpenBlockThreshold.selector);
        deployer.deploy(address(registry), 0);
    }

    function test_installBatch_matchesSafeTransactionBuilderSchema() public {
        CredibleSafeGuard guard = deployer.deploy(address(registry), THRESHOLD);
        string memory json = generator.buildInstallBatch(address(safe), address(guard), block.chainid, CREATED_AT);

        assertEq(vm.parseJsonString(json, ".version"), "1.0");
        assertEq(vm.parseJsonString(json, ".chainId"), vm.toString(block.chainid));
        assertEq(vm.parseJsonUint(json, ".createdAt"), CREATED_AT);
        assertEq(vm.parseJsonString(json, ".meta.name"), "Install Credible Safe Guard");
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), address(safe));
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), address(safe));
        assertEq(vm.parseJsonString(json, ".transactions[0].value"), "0");
        assertEq(vm.parseJsonString(json, ".transactions[0].contractMethod.name"), "setGuard");
        assertFalse(vm.parseJsonBool(json, ".transactions[0].contractMethod.payable"));
        assertEq(vm.parseJsonString(json, ".transactions[0].contractMethod.inputs[0].name"), "guard");
        assertEq(vm.parseJsonString(json, ".transactions[0].contractMethod.inputs[0].type"), "address");
        assertEq(vm.parseJsonAddress(json, ".transactions[0].contractInputsValues.guard"), address(guard));
        assertTrue(vm.keyExistsJson(json, ".transactions[0].data"));

        bytes32 expected = generator.calculateChecksum(address(safe), address(guard), block.chainid, CREATED_AT);
        assertEq(vm.parseJsonBytes32(json, ".meta.checksum"), expected);
    }

    function test_removeBatch_targetsZeroGuard() public {
        string memory json = generator.buildRemoveBatch(address(safe), block.chainid, CREATED_AT);

        assertEq(vm.parseJsonString(json, ".meta.name"), "Remove Credible Safe Guard");
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), address(safe));
        assertEq(vm.parseJsonString(json, ".transactions[0].contractMethod.name"), "setGuard");
        assertEq(vm.parseJsonAddress(json, ".transactions[0].contractInputsValues.guard"), address(0));
        assertEq(
            vm.parseJsonBytes32(json, ".meta.checksum"),
            generator.calculateChecksum(address(safe), address(0), block.chainid, CREATED_AT)
        );
    }

    function test_checksum_matchesSafeReferenceAlgorithm() public view {
        bytes32 checksum = generator.calculateChecksum(address(0x1111), address(0x2222), 1, 1_700_000_000_000);
        assertEq(checksum, REFERENCE_CHECKSUM);
    }

    function test_generatedInstallBatch_executesThroughRealSafe() public {
        CredibleSafeGuard guard = deployer.deploy(address(registry), THRESHOLD);
        string memory json = generator.buildInstallBatch(address(safe), address(guard), block.chainid, CREATED_AT);

        _executeGeneratedBatch(json);
        assertEq(_installedGuard(), address(guard));
    }

    function test_generatedBatch_replacesAndRemovesGuard() public {
        CredibleSafeGuard firstGuard = deployer.deploy(address(registry), THRESHOLD);
        CredibleSafeGuard secondGuard = deployer.deploy(address(registry), THRESHOLD + 1);

        _executeGeneratedBatch(
            generator.buildInstallBatch(address(safe), address(firstGuard), block.chainid, CREATED_AT)
        );
        assertEq(_installedGuard(), address(firstGuard));

        registry.markCurrentBlockCredible();
        _executeGeneratedBatch(
            generator.buildInstallBatch(address(safe), address(secondGuard), block.chainid, CREATED_AT + 1)
        );
        assertEq(_installedGuard(), address(secondGuard));

        registry.markCurrentBlockCredible();
        _executeGeneratedBatch(generator.buildRemoveBatch(address(safe), block.chainid, CREATED_AT + 2));
        assertEq(_installedGuard(), address(0));
    }

    function test_rejectsInvalidSafeAndGuardInputs() public {
        CredibleSafeGuard guard = deployer.deploy(address(registry), THRESHOLD);

        vm.expectRevert(SafeGuardBatch.ZeroSafeAddress.selector);
        generator.buildInstallBatch(address(0), address(guard), block.chainid, CREATED_AT);

        vm.expectRevert(abi.encodeWithSelector(SafeGuardBatch.SafeHasNoCode.selector, address(0xBEEF)));
        generator.buildInstallBatch(address(0xBEEF), address(guard), block.chainid, CREATED_AT);

        vm.expectRevert(SafeGuardBatch.ZeroGuardAddress.selector);
        generator.buildInstallBatch(address(safe), address(0), block.chainid, CREATED_AT);

        vm.expectRevert(abi.encodeWithSelector(SafeGuardBatch.GuardHasNoCode.selector, address(0xBEEF)));
        generator.buildInstallBatch(address(safe), address(0xBEEF), block.chainid, CREATED_AT);

        UnsupportedGuard unsupported = new UnsupportedGuard();
        vm.expectRevert(abi.encodeWithSelector(SafeGuardBatch.UnsupportedGuardInterface.selector, address(unsupported)));
        generator.buildInstallBatch(address(safe), address(unsupported), block.chainid, CREATED_AT);
    }

    function test_rejectsUnknownAction() public {
        vm.expectRevert(abi.encodeWithSelector(SafeGuardBatch.InvalidAction.selector, "replace"));
        generator.parseAction("replace");
    }

    function test_actionPathsAreDistinct() public view {
        assertEq(generator.outputPath(SafeGuardBatch.Action.Install), "safe-guard-output/install.json");
        assertEq(generator.outputPath(SafeGuardBatch.Action.Remove), "safe-guard-output/remove.json");
    }

    function test_run_writesImportableInstallBatch() public {
        CredibleSafeGuard guard = deployer.deploy(address(registry), THRESHOLD);
        vm.setEnv("SAFE_ADDRESS", vm.toString(address(safe)));
        vm.setEnv("SAFE_GUARD_ACTION", "install");
        vm.setEnv("CREDIBLE_SAFE_GUARD", vm.toString(address(guard)));

        (string memory json, string memory path) = generator.run();

        assertEq(path, "safe-guard-output/install.json");
        assertEq(vm.readFile(path), json);
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), address(safe));
        assertEq(vm.parseJsonAddress(json, ".transactions[0].contractInputsValues.guard"), address(guard));
        vm.removeFile(path);
    }

    function _executeGeneratedBatch(string memory json) internal {
        address to = vm.parseJsonAddress(json, ".transactions[0].to");
        address guard = vm.parseJsonAddress(json, ".transactions[0].contractInputsValues.guard");
        bytes memory data = abi.encodeWithSignature("setGuard(address)", guard);
        bytes memory signatures = _signTx(to, data);

        assertTrue(
            safe.execTransaction(to, 0, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signatures)
        );
    }

    function _signTx(address to, bytes memory data) internal view returns (bytes memory) {
        bytes32 txHash =
            safe.getTransactionHash(to, 0, data, Enum.Operation.Call, 0, 0, 0, address(0), address(0), safe.nonce());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, txHash);
        return abi.encodePacked(r, s, v);
    }

    function _installedGuard() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(safe), GUARD_STORAGE_SLOT))));
    }
}
