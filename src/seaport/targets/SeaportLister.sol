// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IERC20} from "../../interfaces/IERC20.sol";
import {IERC721} from "../../interfaces/IERC721.sol";
import {IERC1155} from "../../interfaces/IERC1155.sol";

import {ConsiderationInterface} from "seaport/interfaces/ConsiderationInterface.sol";
import {ItemType, OfferItem} from "seaport/lib/ConsiderationStructs.sol";
import {ISeaportLister, Order, OrderComponents} from "../interfaces/ISeaportLister.sol";

/// @title SeaportLister
/// @author Tessera
/// @notice Target contract for executing the listing and delisting of orders on Seaport
contract SeaportLister is ISeaportLister {
    /// @notice Address of the conduit that is approved to spend the items
    address public immutable conduit;

    constructor(address _conduit) {
        conduit = _conduit;
    }

    /// @notice Approves the conduit to list the offer items
    /// @param _consideration Address of the Consideration contract (Seaport)
    /// @param _orders List of orders being validated
    function validateListing(address _consideration, Order[] memory _orders) external {
        uint256 ordersLength = _orders.length;
        unchecked {
            for (uint256 i; i < ordersLength; ++i) {
                uint256 offerLength = _orders[i].parameters.offer.length;
                for (uint256 j; j < offerLength; ++j) {
                    OfferItem memory offer = _orders[i].parameters.offer[j];
                    address token = offer.token;
                    ItemType itemType = offer.itemType;
                    if (itemType == ItemType.ERC721)
                        IERC721(token).setApprovalForAll(conduit, true);
                    if (itemType == ItemType.ERC1155)
                        IERC1155(token).setApprovalForAll(conduit, true);
                    if (itemType == ItemType.ERC20)
                        IERC20(token).approve(conduit, type(uint256).max);
                }
            }
        }
        // Validates the order on-chain so no signature is required to fill it
        assert(ConsiderationInterface(_consideration).validate(_orders));
    }

    /// @notice Cancels the listing of all offer items
    /// @param _consideration Address of the Consideration contract (Seaport)
    /// @param _orders List of orders being canceled
    function cancelListing(address _consideration, OrderComponents[] memory _orders) external {
        assert(ConsiderationInterface(_consideration).cancel(_orders));
    }
}
