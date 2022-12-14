// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Order, OrderComponents} from "seaport/lib/ConsiderationStructs.sol";

/// @dev Interface for SeaportLister target contract
interface ISeaportLister {
    function cancelListing(address _consideration, OrderComponents[] memory _orders) external;

    function validateListing(address _consideration, Order[] memory _orders) external;
}
