// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {
    AaveV4ExternalCollateralHelpers,
    IExternalAccessControl,
    IExternalBlacklist,
    IExternalBlockedAccount,
    IExternalPausable,
    IExternalTetherBlacklist,
    IExternalTimedBlacklist,
    IExternalTimedPausable
} from "./AaveV4ExternalCollateralHelpers.sol";
import {IAaveV4Spoke} from "./AaveV4Interfaces.sol";

/// @title AaveV4ExternalCollateralTransferabilityAssertion
/// @author Phylax Systems
/// @notice Makes an Aave v4 position reduce-only when its external collateral cannot be seized.
/// @dev Protects against an issuer or protocol independently pausing a token, blacklisting the
///      Aave Hub, blocking the Hub, or assigning it a full transfer-restriction role. Aave's
///      borrow path does not transfer the collateral token, so it can otherwise add debt while
///      the token's native transfer revert is deferred until liquidation. Repay, supply,
///      liquidation, debt-free exits, and complete removal of the impaired collateral remain open.
contract AaveV4ExternalCollateralTransferabilityAssertion is AaveV4ExternalCollateralHelpers {
    enum AdapterKind {
        Unsupported,
        Paused,
        PausedAndBlacklisted,
        PausedAndBlackListed,
        WeEth,
        Blocked,
        FullRestrictedRole
    }

    struct CollateralPolicy {
        uint256 reserveId;
        address token;
        address hub;
        address statusSource;
        AdapterKind adapter;
    }

    // Snapshot reads are deliberately bounded to one external collateral per assertion instance.
    // A five-policy Main Spoke fixture consumed about 575k assertion gas, above the current 300k
    // local executor limit. Deploy one instance per reserve instead of creating an unsafe bundle.
    uint256 internal constant MAX_POLICY_COUNT = 1;
    bytes32 internal constant FULL_RESTRICTED_STAKER_ROLE = keccak256("FULL_RESTRICTED_STAKER_ROLE");
    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Verified Ethereum weETH implementations. The legacy implementation had no transfer pause or
    // blacklist hooks. The restricted implementation added paused(), pausedUntil(), and the
    // external Blacklister hook. Unknown proxy implementations fail closed below.
    address internal constant WEETH_LEGACY_UNRESTRICTED_IMPLEMENTATION = 0x2d10683E941275D502173053927AD6066e6aFd6B;
    address internal constant WEETH_RESTRICTED_IMPLEMENTATION = 0xA6Ca0607190d03CF16fe6F2865Cf40c3D160ccf3;

    address internal immutable SPOKE;
    CollateralPolicy[] internal collateralPolicies;

    /// @param spoke_ The exact Aave v4 risk Spoke adopting the assertion.
    /// @param policies_ Exactly one reserve/token/Hub policy for collateral enabled on that Spoke.
    ///        `statusSource` is the token itself except for weETH, where it is the Blacklister.
    constructor(address spoke_, CollateralPolicy[] memory policies_) {
        require(spoke_ != address(0), "AaveV4Transferability: spoke zero");
        require(policies_.length == MAX_POLICY_COUNT, "AaveV4Transferability: one policy required");

        SPOKE = spoke_;
        for (uint256 i; i < policies_.length; ++i) {
            CollateralPolicy memory policy = policies_[i];
            require(policy.token != address(0), "AaveV4Transferability: token zero");
            require(policy.hub != address(0), "AaveV4Transferability: Hub zero");
            require(policy.statusSource != address(0), "AaveV4Transferability: status source zero");
            require(policy.adapter != AdapterKind.Unsupported, "AaveV4Transferability: unsupported adapter");
            if (policy.adapter != AdapterKind.WeEth) {
                require(policy.statusSource == policy.token, "AaveV4Transferability: status source must be token");
            }
            for (uint256 j; j < i; ++j) {
                require(
                    collateralPolicies[j].reserveId != policy.reserveId,
                    "AaveV4Transferability: duplicate reserve policy"
                );
            }
            collateralPolicies.push(policy);
        }
    }

    /// @notice Registers only Aave operations that can add debt or remove effective collateral.
    /// @dev Function-call triggers are required to decode `onBehalfOf` and bind the check to that
    ///      operation's PostCall position. ERC20-change triggers would miss the failure because an
    ///      Aave borrow against disabled collateral does not move that collateral token.
    function triggers() external view override {
        registerFnCallTrigger(this.assertExternalCollateralTransferable.selector, IAaveV4Spoke.borrow.selector);
        registerFnCallTrigger(this.assertExternalCollateralTransferable.selector, IAaveV4Spoke.withdraw.selector);
        registerFnCallTrigger(
            this.assertExternalCollateralTransferable.selector, IAaveV4Spoke.setUsingAsCollateral.selector
        );
    }

    /// @notice Requires every covered collateral still supporting the affected user's debt to be transferable.
    /// @dev Reads Aave only to scope exposure, then reads independent issuer state at PreCall and
    ///      PostTx. A failure means the triggering operation would leave more debt, or less good
    ///      collateral, while seizure of a relied-on external token can revert. Checking both
    ///      snapshots also rejects pause/blacklist changes wrapped around the Aave call in one tx.
    function assertExternalCollateralTransferable() external view {
        _requireAdopter(SPOKE, "AaveV4Transferability: configured Spoke is not adopter");

        PhEvm.TriggerContext memory ctx = ph.context();
        (address user, bool riskIncreasing) = _riskIncreasingUser(SPOKE, ctx);
        if (!riskIncreasing) {
            return;
        }

        PhEvm.ForkId memory postCall = _postCall(ctx.callEnd);
        PhEvm.ForkId memory preCall = _preCall(ctx.callStart);
        PhEvm.ForkId memory postTx = _postTx();

        for (uint256 i; i < collateralPolicies.length; ++i) {
            CollateralPolicy memory policy = collateralPolicies[i];
            if (!_isActiveCollateralAt(SPOKE, policy.reserveId, user, postCall)) {
                continue;
            }

            IAaveV4Spoke.Reserve memory reserve = _spokeReserveAt(SPOKE, policy.reserveId, postCall);
            require(reserve.underlying == policy.token, "AaveV4Transferability: reserve token changed");
            require(reserve.hub == policy.hub, "AaveV4Transferability: reserve Hub changed");

            require(
                _isTransferableAt(policy, preCall), "AaveV4Transferability: collateral restricted before risk increase"
            );
            require(
                _isTransferableAt(policy, postTx), "AaveV4Transferability: collateral restricted at transaction end"
            );
        }
    }

    function collateralPolicyCount() external view returns (uint256) {
        return collateralPolicies.length;
    }

    function collateralPolicy(uint256 index) external view returns (CollateralPolicy memory) {
        return collateralPolicies[index];
    }

    function _isTransferableAt(CollateralPolicy memory policy, PhEvm.ForkId memory fork) internal view returns (bool) {
        if (policy.adapter == AdapterKind.Paused) {
            return !_pausedAt(policy.token, fork);
        }

        if (policy.adapter == AdapterKind.PausedAndBlacklisted) {
            return !_pausedAt(policy.token, fork)
                && !_readBoolAt(policy.token, abi.encodeCall(IExternalBlacklist.isBlacklisted, (policy.hub)), fork);
        }

        if (policy.adapter == AdapterKind.PausedAndBlackListed) {
            return !_pausedAt(policy.token, fork)
                && !_readBoolAt(
                policy.token, abi.encodeCall(IExternalTetherBlacklist.isBlackListed, (policy.hub)), fork
            );
        }

        if (policy.adapter == AdapterKind.WeEth) {
            address implementation =
                address(uint160(uint256(ph.loadStateAt(policy.token, ERC1967_IMPLEMENTATION_SLOT, fork))));
            if (implementation == WEETH_LEGACY_UNRESTRICTED_IMPLEMENTATION) {
                return true;
            }
            require(
                implementation == address(0) || implementation == WEETH_RESTRICTED_IMPLEMENTATION,
                "AaveV4Transferability: unsupported weETH implementation"
            );

            bool indefinitePause = _pausedAt(policy.token, fork);
            uint256 timedPause = _readUintAt(policy.token, abi.encodeCall(IExternalTimedPausable.pausedUntil, ()), fork);
            uint256 hubBlacklist = _readUintAt(
                policy.statusSource, abi.encodeCall(IExternalTimedBlacklist.blacklistedUntil, (policy.hub)), fork
            );
            return !indefinitePause && timedPause < block.timestamp && hubBlacklist <= block.timestamp;
        }

        if (policy.adapter == AdapterKind.Blocked) {
            return !_readBoolAt(policy.token, abi.encodeCall(IExternalBlockedAccount.isBlocked, (policy.hub)), fork);
        }

        if (policy.adapter == AdapterKind.FullRestrictedRole) {
            return !_readBoolAt(
                policy.token,
                abi.encodeCall(IExternalAccessControl.hasRole, (FULL_RESTRICTED_STAKER_ROLE, policy.hub)),
                fork
            );
        }

        revert("AaveV4Transferability: unsupported adapter");
    }

    function _pausedAt(address target, PhEvm.ForkId memory fork) internal view returns (bool) {
        return _readBoolAt(target, abi.encodeCall(IExternalPausable.paused, ()), fork);
    }
}

/// @title AaveV4EthereumMainSpokeWeETHTransferabilityAssertion
/// @notice Production-configured weETH reduce-only gate for the Ethereum Main Spoke.
/// @dev Constants were verified at Ethereum block 25,653,183. Revalidate the Spoke reserve,
///      Hub, weETH implementation, and Blacklister before adopting after any protocol upgrade.
contract AaveV4EthereumMainSpokeWeETHTransferabilityAssertion is AaveV4ExternalCollateralTransferabilityAssertion {
    address public constant MAIN_SPOKE = 0x94e7A5dCbE816e498b89aB752661904E2F56c485;
    address public constant CORE_HUB = 0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9;
    address public constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address public constant WEETH_BLACKLISTER = 0x5585996E7cFE95f2D99e61168B8b35C66Ff99B18;

    constructor() AaveV4ExternalCollateralTransferabilityAssertion(MAIN_SPOKE, _policies(2)) {}

    function _policies(uint256 reserveId) private pure returns (CollateralPolicy[] memory policies) {
        policies = new CollateralPolicy[](1);
        policies[0] = CollateralPolicy(reserveId, WEETH, CORE_HUB, WEETH_BLACKLISTER, AdapterKind.WeEth);
    }
}

/// @title AaveV4EthereumEtherFiSpokeWeETHTransferabilityAssertion
/// @notice Production-configured weETH reduce-only gate for the Ethereum ether.fi eSpoke.
/// @dev This protects the same Core Hub custody path as the Main Spoke wrapper, with reserve id 0.
contract AaveV4EthereumEtherFiSpokeWeETHTransferabilityAssertion is AaveV4ExternalCollateralTransferabilityAssertion {
    address public constant ETHERFI_ESPOKE = 0xbF10BDfE177dE0336aFD7fcCF80A904E15386219;
    address public constant CORE_HUB = 0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9;
    address public constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address public constant WEETH_BLACKLISTER = 0x5585996E7cFE95f2D99e61168B8b35C66Ff99B18;

    constructor() AaveV4ExternalCollateralTransferabilityAssertion(ETHERFI_ESPOKE, _policies(0)) {}

    function _policies(uint256 reserveId) private pure returns (CollateralPolicy[] memory policies) {
        policies = new CollateralPolicy[](1);
        policies[0] = CollateralPolicy(reserveId, WEETH, CORE_HUB, WEETH_BLACKLISTER, AdapterKind.WeEth);
    }
}
