// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";

contract TreasuryConnector {
    address public owner;
    address public feeCollector;

    // Shares in basis points (parts per 10_000)
    uint16 public treasuryBps; // e.g., 8000 => 80%
    uint16 public insuranceBps; // e.g., 2000 => 20%

    struct Balances {
        uint256 treasury;
        uint256 insurance;
    }

    // token => balances
    mapping(address => Balances) public balances;

    error Unauthorized();
    error InvalidBps();
    error InsufficientBalance();
    error ZeroAddress();
    error TransferFailed();

    event FeeDeposited(address indexed token, uint256 amount, uint256 treasuryAmount, uint256 insuranceAmount);
    event TreasuryWithdrawn(address indexed token, address indexed to, uint256 amount);
    event InsuranceWithdrawn(address indexed token, address indexed to, uint256 amount);
    event FeeCollectorUpdated(address indexed collector);
    event SharesUpdated(uint16 treasuryBps, uint16 insuranceBps);

    constructor(address _feeCollector, uint16 _treasuryBps, uint16 _insuranceBps) {
        owner = msg.sender;
        if (_feeCollector == address(0)) revert ZeroAddress();
        feeCollector = _feeCollector;
        _setShares(_treasuryBps, _insuranceBps);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyFeeCollector() {
        if (msg.sender != feeCollector) revert Unauthorized();
        _;
    }

    function setFeeCollector(address _collector) external onlyOwner {
        if (_collector == address(0)) revert ZeroAddress();
        feeCollector = _collector;
        emit FeeCollectorUpdated(_collector);
    }

    function setShares(uint16 _treasuryBps, uint16 _insuranceBps) external onlyOwner {
        _setShares(_treasuryBps, _insuranceBps);
        emit SharesUpdated(_treasuryBps, _insuranceBps);
    }

    function _setShares(uint16 _treasuryBps, uint16 _insuranceBps) internal {
        if (uint256(_treasuryBps) + uint256(_insuranceBps) != 10000) revert InvalidBps();
        treasuryBps = _treasuryBps;
        insuranceBps = _insuranceBps;
    }

    /// @notice Deposit protocol fee tokens. Callable by the configured `feeCollector` (e.g., PoolManager)
    function depositFee(address token, uint256 amount) external onlyFeeCollector {
        if (amount == 0) return;

        if (!IERC20Minimal(token).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        uint256 insuranceAmount = (amount * insuranceBps) / 10000;
        uint256 treasuryAmount = amount - insuranceAmount;

        Balances storage balance = balances[token];
        balance.insurance += insuranceAmount;
        balance.treasury += treasuryAmount;

        emit FeeDeposited(token, amount, treasuryAmount, insuranceAmount);
    }

    /// @notice Withdraw available treasury funds
    function withdrawTreasury(address token, address to, uint256 amount) external onlyOwner {
        Balances storage balance = balances[token];
        if (balance.treasury < amount) revert InsufficientBalance();
        balance.treasury -= amount;
        if (!IERC20Minimal(token).transfer(to, amount)) revert TransferFailed();
        emit TreasuryWithdrawn(token, to, amount);
    }

    /// @notice Withdraw available insurance funds
    function withdrawInsurance(address token, address to, uint256 amount) external onlyOwner {
        Balances storage balance = balances[token];
        if (balance.insurance < amount) revert InsufficientBalance();
        balance.insurance -= amount;
        if (!IERC20Minimal(token).transfer(to, amount)) revert TransferFailed();
        emit InsuranceWithdrawn(token, to, amount);
    }

    /// @notice View function to get both balances for a token
    function getBalances(address token) external view returns (uint256 treasury, uint256 insurance) {
        Balances memory b = balances[token];
        return (b.treasury, b.insurance);
    }
}
