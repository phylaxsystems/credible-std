// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal ERC20 with cheat helpers (`setBalance`, `mint`, `burn`) so a single armed
///         transaction can drive any pre/post balance the Lido assertions read.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) public {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    /// @dev Overwrites a balance and keeps `totalSupply` consistent.
    function setBalance(address account, uint256 amount) public {
        totalSupply = totalSupply - balanceOf[account] + amount;
        balanceOf[account] = amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

/// @notice wstETH stand-in: an ERC20 that also reports Lido's `stEthPerToken()` rate.
contract MockWstETH is MockERC20 {
    uint256 public rate = 1e18;

    constructor() MockERC20("Wrapped stETH", "wstETH", 18) {}

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function stEthPerToken() external view returns (uint256) {
        return rate;
    }
}

/// @notice Chainlink aggregator stand-in with fully settable round data so the staleness and
///         round-integrity paths can be exercised directly.
contract MockChainlinkFeed {
    uint80 public roundId = 1;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound = 1;

    constructor(int256 answer_, uint256 updatedAt_) {
        answer = answer_;
        startedAt = updatedAt_;
        updatedAt = updatedAt_;
    }

    function setAnswer(int256 answer_) external {
        answer = answer_;
    }

    function setUpdatedAt(uint256 updatedAt_) external {
        updatedAt = updatedAt_;
    }

    function setRound(uint80 roundId_, int256 answer_, uint256 updatedAt_, uint80 answeredInRound_) external {
        roundId = roundId_;
        answer = answer_;
        startedAt = updatedAt_;
        updatedAt = updatedAt_;
        answeredInRound = answeredInRound_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}

/// @notice Generic `getRate()` source (Veda accountant / Balancer-style provider / Mellow oracle).
contract MockRateSource {
    uint256 public rate;
    bool public reverts;

    constructor(uint256 rate_) {
        rate = rate_;
    }

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function setReverts(bool reverts_) external {
        reverts = reverts_;
    }

    function getRate() external view returns (uint256) {
        require(!reverts, "MockRate: unavailable");
        return rate;
    }
}

/// @notice Aave v3-like pool stand-in tracking one account's position.
contract MockAavePool {
    struct Account {
        uint256 collateralBase;
        uint256 debtBase;
        uint256 healthFactor;
    }

    mapping(address => Account) internal account;

    function setAccount(address user, uint256 collateralBase, uint256 debtBase, uint256 healthFactor) external {
        account[user] = Account(collateralBase, debtBase, healthFactor);
    }

    function getUserAccountData(address user)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256)
    {
        Account memory a = account[user];
        uint256 hf = a.debtBase == 0 ? type(uint256).max : a.healthFactor;
        return (a.collateralBase, a.debtBase, 0, 0, 0, hf);
    }
}

/// @notice Aave v3-like oracle stand-in returning a configurable per-asset price.
contract MockAaveOracle {
    mapping(address => uint256) public priceOf;

    function setPrice(address asset, uint256 price) external {
        priceOf[asset] = price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return priceOf[asset];
    }
}

/// @notice Universal vault/strategy-executor adopter. As the assertion's `vault` account it holds
///         the position and balances; its mutators let a single armed transaction move the state
///         the risk and exit-buffer assertions read at the transaction boundary.
contract MockLidoVault {
    function setPosition(MockAavePool pool, uint256 collateralBase, uint256 debtBase, uint256 healthFactor) public {
        pool.setAccount(address(this), collateralBase, debtBase, healthFactor);
    }

    function setSupplied(MockERC20 supplyToken, uint256 amount) public {
        supplyToken.setBalance(address(this), amount);
    }

    function setSelfDebt(MockERC20 debtToken, uint256 amount) public {
        debtToken.setBalance(address(this), amount);
    }

    /// @dev Grow the position and the vault's tracked debt token balance in one transaction.
    function borrowMore(
        MockAavePool pool,
        uint256 collateralBase,
        uint256 debtBase,
        uint256 healthFactor,
        MockERC20 debtToken,
        uint256 vaultDebt
    ) external {
        setPosition(pool, collateralBase, debtBase, healthFactor);
        setSelfDebt(debtToken, vaultDebt);
    }

    function transferOut(MockERC20 token, address to, uint256 amount) external {
        token.transfer(to, amount);
    }
}

/// @notice Share-token adopter for the peg assertion. Supply changes (mint/burn) mark entries and
///         exits; the poke helpers let a transaction touching the share token also move the wstETH
///         rate / provider so the rate-integrity check can be exercised.
contract MockShareToken is MockERC20 {
    constructor() MockERC20("Lido Vault Share", "lvSHARE", 18) {}

    function setWstEthRate(MockWstETH wstEth, uint256 rate) external {
        wstEth.setRate(rate);
    }

    function setProviderRate(MockRateSource provider, uint256 rate) external {
        provider.setRate(rate);
    }
}
