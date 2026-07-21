// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Shared mocks for the anomaly-gated assertion tests. The protocol under protection is `Vault`;
// the others are the external surfaces the damage heuristics read: an ERC20 whose Transfer events
// the flow precompiles decode, an asset-priced oracle, and an ERC4626-shaped vault.

/// @notice Minimal ERC20 that emits the Transfer events the flow precompiles read.
contract MockERC20 {
    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
}

/// @notice Mock asset-priced oracle with an arg-taking reader. `getAssetPrice(address)` is the
/// query shape a bare `bytes4` selector cannot encode, so it exercises the full-`bytes` oracle
/// query path.
contract MockOracle {
    mapping(address => uint256) internal price;

    function setPrice(address asset, uint256 p) external {
        price[asset] = p;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return price[asset];
    }
}

/// @notice Minimal ERC4626-shaped vault the accounting precompile reads: share price is
/// `totalAssets / totalSupply`. `setAssets` moves it.
contract MockVault4626 {
    uint256 public totalAssets;
    uint256 public totalSupply;

    constructor(uint256 assets_, uint256 supply_) {
        totalAssets = assets_;
        totalSupply = supply_;
    }

    function setAssets(uint256 a) external {
        totalAssets = a;
    }
}

/// @notice Holds the token; `drain` sends it out, `upgradeTo` writes the EIP-1967 implementation
/// slot, `drainAndUpgrade` does both in one transaction, `upgradeRemote` upgrades another vault,
/// `setOwner` writes the owner slot, `moveOracle` shifts an oracle price, `drainWithFlag` sets a
/// health flag alongside a drain, `poke` touches nothing.
contract Vault {
    /// @notice A namespaced owner slot (OZ Ownable v5 style) the `ownerSlot` heuristic can watch.
    ///         Deliberately not a plain storage variable: `owner` would pack into slot 0 next to
    ///         `flag`, and slot 0 collides with the heuristic's `bytes32(0)` disabled sentinel.
    bytes32 public constant OWNER_SLOT = keccak256("credible.anomaly.mock.owner");

    MockERC20 public immutable token;
    /// A protocol-specific health flag an `_extra` leg can read; false = unhealthy. Slot 0.
    bool public flag;

    constructor(MockERC20 token_) {
        token = token_;
    }

    function drain(address to, uint256 amount) external {
        token.transfer(to, amount);
    }

    function drainWithFlag(address to, uint256 amount, bool f) external {
        flag = f;
        token.transfer(to, amount);
    }

    function upgradeTo(address impl) external {
        assembly {
            sstore(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc, impl)
        }
    }

    function drainAndUpgrade(address to, uint256 amount, address impl) external {
        token.transfer(to, amount);
        assembly {
            sstore(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc, impl)
        }
    }

    function upgradeRemote(Vault remote, address impl) external {
        remote.upgradeTo(impl);
    }

    function setOwner(address newOwner) external {
        bytes32 slot = OWNER_SLOT;
        assembly {
            sstore(slot, newOwner)
        }
    }

    function moveOracle(address oracle, address asset, uint256 newPrice) external {
        MockOracle(oracle).setPrice(asset, newPrice);
    }

    function moveSharePrice(address vault4626, uint256 newAssets) external {
        MockVault4626(vault4626).setAssets(newAssets);
    }

    function poke() external {}
}
