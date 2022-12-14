// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Order, OfferItem, OrderComponents} from "seaport/lib/ConsiderationStructs.sol";
import {Permission} from "../../interfaces/IVaultRegistry.sol";

/// @dev Listing information
struct Listing {
    // Address of proposer creating listing
    address proposer;
    // Amount of tokens put up for collateral
    uint256 collateral;
    // Ether price per token
    uint256 pricePerToken;
    // Timestamp of proposal creation
    uint256 proposalDate;
    // Seaport Order for the vault
    Order order;
}

/// @dev Interface for OptimisticListingSeaport module contract
interface IOptimisticListingSeaport {
    /// @dev Emitted when the vault already has an active proposal
    error AlreadyActive();
    /// @dev Emitted when the collateral is less than the amount being bought
    error InsufficientCollateral();
    /// @dev Emitted when the payment amount is incorrect
    error InvalidPayment();
    /// @dev Emitted when the caller is not the VaultRegistry
    error NotAuthorized();
    /// @dev Emitted when the caller does not have enough fractional tokens
    error NotEnoughTokens();
    /// @dev Emitted when the current listing is greater than the new listing
    error NotLower();
    /// @dev Emitted when the vault is not owner of the NFT
    error NotOwner();
    /// @dev Emitted when the caller is the not the proposer of the new listing
    error NotProposer();
    /// @dev Emitted when the current listing is not rejected
    error NotRejected();
    /// @dev Emitted when the NFT has not been sold
    error NotSold();
    /// @dev Emitted when the address is not a registered vault
    error NotVault(address _vault);
    /// @dev Emitted when the new listing is rejected
    error Rejected();
    /// @dev Emitted when the listing time is still active
    error TimeNotElapsed();

    /// @dev Event log proposing a new listing
    event Propose(
        address indexed _vault,
        address indexed _proposer,
        uint256 _collateral,
        uint256 _pricePerToken,
        Order _order
    );
    /// @dev Event log for rejecting a proposed listing
    event RejectProposal(
        address indexed _vault,
        address indexed _rejecter,
        uint256 _amount,
        uint256 _payment,
        Order _order
    );
    /// @dev Event log for rejecting an active listing
    event RejectActive(
        address indexed _vault,
        address indexed _rejecter,
        uint256 _amount,
        uint256 _payment,
        Order _order
    );
    /// @dev Event log listing an order on Seaport
    event List(address indexed _vault, uint256 _newPrice, Order _order);
    /// @dev Event log for delisting an order from the marketplace
    event Delist(address indexed _vault, Order _order);
    /// @dev Event log for canceling an active listing
    event Cancel(address indexed _vault, Order _order);
    /// @dev Event log for cashing out from the sale of an active listing
    event Cash(address indexed _vault, address indexed _user, uint256 _amount);
    /// @dev Event log for withdrawing collateral amount from pending balances
    event WithdrawCollateral(address indexed _vault, address indexed _user, uint256 _amount);

    function OPENSEA_RECIPIENT() external view returns (address payable);

    function PROPOSAL_PERIOD() external view returns (uint256);

    function activeListings(address)
        external
        view
        returns (
            address proposer,
            uint256 collateral,
            uint256 pricePerToken,
            uint256 proposalDate,
            Order memory order
        );

    function cancel(address _vault, bytes32[] calldata _delistProof) external;

    function cash(address _vault, bytes32[] calldata _burnProof) external;

    function conduitKey() external view returns (bytes32);

    function feeReceiver() external view returns (address payable);

    function getPermissions() external view returns (Permission[] memory permissions);

    function list(address _vault, bytes32[] calldata _listProof) external;

    function pendingBalances(address, address) external view returns (uint256);

    function propose(
        address _vault,
        uint256 _collateral,
        uint256 _valuePerToken,
        OfferItem[] calldata _offer
    ) external;

    function proposedListings(address)
        external
        view
        returns (
            address proposer,
            uint256 collateral,
            uint256 pricePerToken,
            uint256 proposalDate,
            Order memory order
        );

    function registry() external view returns (address);

    function rejectActive(
        address _vault,
        uint256 _amount,
        bytes32[] calldata _delistProof
    ) external payable;

    function rejectProposal(address _vault, uint256 _amount) external payable;

    function seaport() external view returns (address);

    function seaportLister() external view returns (address);

    function supply() external view returns (address);

    function updateFeeReceiver(address payable _new) external;

    function vaultOrderHash(address) external view returns (bytes32);

    function withdrawCollateral(address _vault, address _to) external;

    function zone() external view returns (address);
}
