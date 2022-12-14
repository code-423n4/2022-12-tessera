// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IMarketBuyer} from "../../interfaces/IMarketBuyer.sol";

interface IPunksMarketBuyer is IMarketBuyer {
    function listing() external view returns (address);

    function proxy() external view returns (address);

    function registry() external view returns (address);

    function wrapper() external view returns (address);
}
