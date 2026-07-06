// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Minimal reproduction of the Lazy Summer Protocol (Summer.fi) FleetCommander/Ark
///        accounting flaw exploited on 2026-07-06 (tx 0x0db528c4...).
///
/// Real architecture (mainnet):
///   - FleetCommander (e.g. LazyVault_LowerRisk_USDC, 0x98c4...cf17) is an ERC-4626 vault.
///   - Its `totalAssets()` is the sum of a USDC buffer plus every Ark's `totalAssets()`.
///   - An Ark wraps an external yield source. The Varlamore Ark valued its position by the
///     amount of external vault shares (vgUSDC, 0x8399...c78f) it *held* — a live on-chain
///     balance, not internally-tracked principal.
///
/// The flaw: because an Ark derives its reported assets from a token balance that ANY address
/// can increase by a direct transfer ("donation"), an attacker can inflate
/// `FleetCommander.totalAssets()` mid-transaction with no corresponding share mint, pump the
/// vault share price, and redeem freshly-minted shares against the real USDC buffer at the
/// inflated price. Honest depositors are left holding shares "backed" by the donated (cheaply
/// acquired, over-counted) external tokens.
///
/// This file models that exact accounting shape with the smallest faithful surface. The prior
/// manipulation that let the attacker obtain vgUSDC far below the Ark's face valuation is
/// abstracted away (the attacker is simply given vgUSDC in setup); the reproduced defect is the
/// Ark counting a donatable external balance at face value, which is what moves the vault's
/// share price.

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

/// @notice Barebones 6-decimal ERC-20 used for both USDC and the external vgUSDC share token.
contract MockToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

/// @notice A FleetCommander Ark whose reported assets equal the external-vault-share balance it
///         currently holds, valued at par. This is the donation-sensitive component.
contract Ark {
    IERC20Like public immutable vgToken; // external yield-source shares (vgUSDC)
    address public immutable fleet;

    constructor(address _vgToken, address _fleet) {
        vgToken = IERC20Like(_vgToken);
        fleet = _fleet;
    }

    /// @notice Reported assets = live vgUSDC balance held by this Ark, valued 1:1.
    /// @dev The defect: a direct `vgToken.transfer(ark, x)` raises this with no share mint in
    ///      the FleetCommander. Principal is not tracked internally.
    function totalAssets() external view returns (uint256) {
        return vgToken.balanceOf(address(this));
    }

    /// @notice FleetCommander seeds the Ark with an initial (legitimate) vgUSDC position.
    function seed(uint256 vgAmount) external {
        require(msg.sender == fleet, "only fleet");
        // pulled from the fleet which already holds vgToken for boarding
        require(vgToken.transferFrom(fleet, address(this), vgAmount), "seed xfer");
    }
}

/// @notice Minimal ERC-4626-style FleetCommander vault.
///         totalAssets() = USDC buffer held here + Ark.totalAssets().
contract FleetCommander {
    string public constant name = "LazyVault_LowerRisk_USDC (repro)";
    string public constant symbol = "LVUSDC";
    uint8 public constant decimals = 6;

    IERC20Like public immutable usdc;
    Ark public ark;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    constructor(address _usdc) {
        usdc = IERC20Like(_usdc);
    }

    function setArk(address _ark) external {
        ark = Ark(_ark);
    }

    function asset() external view returns (address) {
        return address(usdc);
    }

    /// @notice Buffer USDC held directly by the vault plus assets reported by the Ark.
    function totalAssets() public view returns (uint256) {
        uint256 arkAssets = address(ark) == address(0) ? 0 : ark.totalAssets();
        return usdc.balanceOf(address(this)) + arkAssets;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 ts = totalSupply;
        uint256 ta = totalAssets();
        if (ts == 0 || ta == 0) return assets;
        return (assets * ts) / ta;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 ts = totalSupply;
        if (ts == 0) return shares;
        return (shares * totalAssets()) / ts;
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = convertToShares(assets);
        require(usdc.transferFrom(msg.sender, address(this), assets), "deposit xfer");
        totalSupply += shares;
        balanceOf[receiver] += shares;
        emit Transfer(address(0), receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = convertToAssets(shares);
        if (msg.sender != owner) {
            // (allowance path omitted; attacker owns its own shares in the repro)
            revert("no allowance");
        }
        balanceOf[owner] -= shares;
        totalSupply -= shares;
        emit Transfer(owner, address(0), shares);
        // Redemptions are paid from the real USDC buffer held by the vault.
        require(usdc.transfer(receiver, assets), "redeem: buffer short");
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /// @dev Test-only helper: move USDC buffer into the Ark as vgUSDC (a legitimate allocation).
    ///      Mirrors the FleetCommander boarding funds into an Ark. Kept permissionless for the
    ///      repro harness.
    function board(uint256 usdcAmount, address vgToken) external {
        // Vault sends USDC out (to a sink standing in for the external vault) and the equivalent
        // vgUSDC is minted to the Ark. Net effect on totalAssets is neutral at par.
        require(usdc.transfer(address(0xdead), usdcAmount), "board xfer");
        MockToken(vgToken).mint(address(ark), usdcAmount);
    }
}
