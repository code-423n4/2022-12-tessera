// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMarketBuyer {
    function execute(bytes memory _order) external payable returns (address vault);
}
