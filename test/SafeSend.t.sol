// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.13;

import "./TestUtil.sol";
import {MockSender} from "../src/mocks/MockSender.sol";
import {MockEthReceiver, MockEthNotReceiver} from "../src/mocks/MockEthReceiver.sol";

contract SafeSendTest is TestUtil {
    MockSender sender;
    MockEthReceiver ethReceiver;
    MockEthNotReceiver wethReceiver;

    /// =================
    /// ===== SETUP =====
    /// =================
    function setUp() public {
        weth = new WETH();

        sender = new MockSender(payable(address(weth)));
        ethReceiver = new MockEthReceiver();
        wethReceiver = new MockEthNotReceiver();

        vm.deal(address(sender), 10 ether);
        vm.label(address(sender), "SafeSend");
        vm.label(address(ethReceiver), "EthReceiver");
        vm.label(address(wethReceiver), "WETHReceiver");
    }

    function testSendEth() public {
        sender.sendEthOrWeth(address(ethReceiver), 10 ether);
    }

    function testSendWETH() public {
        sender.sendEthOrWeth(address(wethReceiver), 10 ether);
    }
}
