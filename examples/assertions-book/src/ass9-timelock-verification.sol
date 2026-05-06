// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract TimelockVerification {
    struct Timelock {
        uint256 timelockDelay;
        bool isActive;
    }

    Timelock private _timelock;

    constructor() {
        _timelock = Timelock({timelockDelay: 1 days, isActive: false});
    }

    function timelockActive() external view returns (bool) {
        return _timelock.isActive;
    }

    function timelockDelay() external view returns (uint256) {
        return _timelock.timelockDelay;
    }

    function activateTimelock() external {
        _timelock.isActive = true;
    }

    function setTimelock(uint256 _delay) external {
        _timelock.isActive = true;
        _timelock.timelockDelay = _delay;
    }
}
