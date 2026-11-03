// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC404} from "../../../lib/erc404/contracts/ERC404.sol";
import {CredibleTest} from "../../../src/CredibleTest.sol";
import {SafeTxShapeAssertion} from "../../../src/protection/safe/SafeTxShapeAssertion.sol";
import {SafeTxShapeHelpers} from "../../../src/protection/safe/SafeTxShapeHelpers.sol";

// Only the Safe entrypoint ABI is modeled here; the upstream token really executes.
contract ApprovalCaller {
    function execTransactionFromModule(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        returns (bool)
    {
        require(operation == 0);
        (bool success,) = to.call{value: value}(data);
        require(success);
        return success;
    }
}

contract DualToken is ERC404 {
    constructor(address holder) ERC404("Dual token", "DUAL", 18) {
        _mintERC20(holder, 1 ether);
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }
}

contract SafeDualTokenApprovalTest is Test, CredibleTest {
    address internal constant SPENDER = address(0x5001);
    ApprovalCaller internal caller;
    DualToken internal token;

    function setUp() public {
        caller = new ApprovalCaller();
        token = new DualToken(address(caller));
    }

    function testErc20CapAlsoAuthorizesNftApprovalOnDualToken() public {
        uint256 tokenId = token.ID_ENCODING_PREFIX() + 1;
        assertEq(token.ownerOf(tokenId), address(caller));
        // ERC-721 ERC-165 detection alone does not identify this upstream hybrid.
        assertFalse(token.supportsInterface(0x80ac58cd));
        _arm(1, tokenId);
        caller.execTransactionFromModule(address(token), 0, abi.encodeCall(token.approve, (SPENDER, tokenId)), 0);
        assertEq(token.getApproved(tokenId), SPENDER);
        assertEq(token.allowance(address(caller), SPENDER), 0);
    }

    function testErc721PolicyAlsoAuthorizesUnlimitedFungibleAllowance() public {
        _arm(3, 0);
        caller.execTransactionFromModule(
            address(token), 0, abi.encodeCall(token.approve, (SPENDER, type(uint256).max)), 0
        );
        assertEq(token.allowance(address(caller), SPENDER), type(uint256).max);
        assertEq(token.getApproved(token.ID_ENCODING_PREFIX() + 1), address(0));
    }

    function testOrdinaryFungibleApprovalUsesTheSameSelector() public {
        _arm(1, 100);
        caller.execTransactionFromModule(address(token), 0, abi.encodeCall(token.approve, (SPENDER, 75)), 0);
        assertEq(token.allowance(address(caller), SPENDER), 75);
        assertEq(token.getApproved(token.ID_ENCODING_PREFIX() + 1), address(0));
    }

    function _arm(uint8 kind, uint256 cap) internal {
        SafeTxShapeHelpers.TargetPolicy[] memory targets = new SafeTxShapeHelpers.TargetPolicy[](1);
        targets[0] = SafeTxShapeHelpers.TargetPolicy(address(token), true, false, false, false);
        SafeTxShapeHelpers.ApprovalPolicy[] memory approvals = new SafeTxShapeHelpers.ApprovalPolicy[](1);
        approvals[0] = SafeTxShapeHelpers.ApprovalPolicy(address(token), SPENDER, kind, cap, false);
        cl.assertion(
            address(caller),
            abi.encodePacked(
                type(SafeTxShapeAssertion).creationCode,
                abi.encode(
                    targets,
                    new SafeTxShapeHelpers.SelectorPolicy[](0),
                    new SafeTxShapeHelpers.BatchExecutorPolicy[](0),
                    approvals,
                    false,
                    new address[](0)
                )
            ),
            SafeTxShapeAssertion.assertSafeApprovalPolicy.selector
        );
    }
}
