// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryConnector} from "../src/TreasuryConnector.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";

contract MockERC20 is IERC20Minimal {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bool public transferFromOk = true;
    bool public transferOk = true;

    function setTransferFromOk(bool ok) external {
        transferFromOk = ok;
    }

    function setTransferOk(bool ok) external {
        transferOk = ok;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        if (!transferOk) return false;
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        if (!transferFromOk) return false;
        uint256 allowed = allowance[sender][msg.sender];
        require(allowed >= amount, "insufficient allowance");
        allowance[sender][msg.sender] = allowed - amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract TreasuryConnectorTest is Test {
    TreasuryConnector connector;
    MockERC20 token;

    function setUp() public {
        connector = new TreasuryConnector(address(this), 8000, 2000);
        token = new MockERC20();
        token.mint(address(this), 1000);
        token.approve(address(connector), 1000);
    }

    function test_depositFeeSplitsFundsAccordingToConfiguredShares() public {
        connector.depositFee(address(token), 100);

        (uint256 treasury, uint256 insurance) = connector.getBalances(address(token));
        assertEq(treasury, 80);
        assertEq(insurance, 20);
        assertEq(token.balanceOf(address(connector)), 100);
    }

    function test_withdrawalsTransferBalancesAndEmptyTheStoredAmounts() public {
        connector.depositFee(address(token), 100);

        uint256 recipientBefore = token.balanceOf(address(this));
        connector.withdrawTreasury(address(token), address(this), 40);
        connector.withdrawInsurance(address(token), address(this), 20);

        (uint256 treasury, uint256 insurance) = connector.getBalances(address(token));
        assertEq(treasury, 40);
        assertEq(insurance, 0);
        assertEq(token.balanceOf(address(this)), recipientBefore + 60);
    }

    function test_zeroDepositDoesNothing() public {
        connector.depositFee(address(token), 0);

        (uint256 treasury, uint256 insurance) = connector.getBalances(address(token));
        assertEq(treasury, 0);
        assertEq(insurance, 0);
    }

    function test_onlyFeeCollectorCanDeposit() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(TreasuryConnector.Unauthorized.selector);
        connector.depositFee(address(token), 1);
    }

    function test_withdrawRevertsWhenBalanceIsInsufficient() public {
        vm.expectRevert(TreasuryConnector.InsufficientBalance.selector);
        connector.withdrawTreasury(address(token), address(this), 1);
    }

    function test_depositFeeRevertsWhenTransferFromFails() public {
        token.setTransferFromOk(false);

        vm.expectRevert(TreasuryConnector.TransferFailed.selector);
        connector.depositFee(address(token), 1);
    }

    function test_withdrawRevertsWhenTransferFails() public {
        connector.depositFee(address(token), 100);
        token.setTransferOk(false);

        vm.expectRevert(TreasuryConnector.TransferFailed.selector);
        connector.withdrawTreasury(address(token), address(this), 1);
    }
}
