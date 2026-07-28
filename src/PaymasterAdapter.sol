// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";

contract PaymasterAdapter {
    address public owner;
    address public settlementRelayer;

    error Unauthorized();
    error ZeroAddress();
    error TransferFailed();

    event SettlementSponsored(address indexed token, address indexed relayer, uint256 amount);

    constructor(address _settlementRelayer) {
        owner = msg.sender;
        if (_settlementRelayer == address(0)) revert ZeroAddress();
        settlementRelayer = _settlementRelayer;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    function setSettlementRelayer(address relayer) external onlyOwner {
        if (relayer == address(0)) revert ZeroAddress();
        settlementRelayer = relayer;
    }

    function sponsorSettlement(address token, address recipient, uint256 amount) external returns (bool success) {
        if (settlementRelayer == address(0)) revert ZeroAddress();
        if (!IERC20Minimal(token).transferFrom(settlementRelayer, recipient, amount)) revert TransferFailed();
        emit SettlementSponsored(token, settlementRelayer, amount);
        return true;
    }
}
