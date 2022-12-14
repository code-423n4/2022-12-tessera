// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

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
}

/// @dev Interface for OptimisticListingPunks module contract
interface IOptimisticListingPunks {
    /// @dev Emitted when the vault has already been registered with the module
    error AlreadyRegistered();
    /// @dev Emitted when the listing has already been settled
    error AlreadySettled();
    /// @dev Emitted when the collateral is less than the amount being bought
    error InsufficientCollateral();
    /// @dev Emitted when the payment amount is incorrect
    error InvalidPayment();
    /// @dev Emitted when the caller is not the VaultRegistry
    error NotAuthorized();
    /// @dev Emitted when the caller does not have enough rae tokens
    error NotEnoughTokens();
    /// @dev Emitted when the current listing is greater than the new listing
    error NotLower();
    /// @dev Emitted when the vault is not owner of the NFT
    error NotOwner();
    /// @dev Emitted when the caller is the not the proposer of the new listing
    error NotProposer();
    /// @dev Emitted when the current listing is not rejected
    error NotRejected();
    /// @dev Emitted when the listing has not been settled after a sale
    error NotSettled();
    /// @dev Emitted when the NFT has not been sold
    error NotSold();
    /// @dev Emitted when the address is not a registered vault
    error NotVault(address _vault);
    /// @dev Emitted when the new listing is rejected
    error Rejected();
    /// @dev Emitted when the listing time is still active
    error TimeNotElapsed();

    /// @dev Event log for registering punk and vault
    event Register(address indexed _vault, uint256 indexed _punkId);
    /// @dev Event log proposing a new listing
    event Propose(
        address indexed _vault,
        address indexed _proposer,
        uint256 _collateral,
        uint256 _pricePerToken
    );
    /// @dev Event log for rejecting a proposed listing
    event RejectProposal(
        address indexed _vault,
        address indexed _rejecter,
        uint256 _amount,
        uint256 _payment
    );
    /// @dev Event log for rejecting an active listing
    event RejectActive(
        address indexed _vault,
        address indexed _rejecter,
        uint256 _amount,
        uint256 _payment
    );
    /// @dev Event log listing a Punk on the marketplace
    event List(address indexed _vault, uint256 indexed _punkId, uint256 _newPrice);
    /// @dev Event log for delisting a Punk from the marketplace
    event Delist(address indexed _vault, uint256 indexed _punkId);
    /// @dev Event log for settling the sale of an active listing
    event Settle(address indexed _vault, uint256 indexed _punkId);
    /// @dev Event log for canceling an active listing
    event Cancel(address indexed _vault, uint256 indexed _punkId);
    /// @dev Event log for cashing out from the sale of an active listing
    event Cash(address indexed _vault, address indexed _user, uint256 _amount);
    /// @dev Event log for withdrawing collateral amount from pending balances
    event WithdrawCollateral(address indexed _vault, address indexed _user, uint256 _amount);

    function PROPOSAL_PERIOD() external view returns (uint256);

    function activeListings(address)
        external
        view
        returns (
            address proposer,
            uint256 collateral,
            uint256 pricePerToken,
            uint256 proposalDate
        );

    function adapters(address) external view returns (address);

    function cancel(address _vault, bytes32[] calldata _delistProof) external;

    function cash(address _vault, bytes32[] calldata _burnProof) external;

    function list(
        address _vault,
        bytes32[] calldata _transferPunkProof,
        bytes32[] calldata _listProof
    ) external;

    function getPermissions() external view returns (Permission[] memory permissions);

    function marketplace() external view returns (address);

    function pendingBalances(address, address) external view returns (uint256);

    function propose(
        address _vault,
        uint256 _collateral,
        uint256 _valuePerToken
    ) external;

    function proposedListings(address)
        external
        view
        returns (
            address proposer,
            uint256 collateral,
            uint256 pricePerToken,
            uint256 proposalDate
        );

    function punks() external view returns (address);

    function register(
        address _vault,
        uint256 _punkId,
        bytes32[] calldata _unwrapProof
    ) external;

    function registry() external view returns (address);

    function rejectActive(
        address _vault,
        uint256 _amount,
        bytes32[] calldata _delistProof
    ) external payable;

    function rejectProposal(address _vault, uint256 _amount) external payable;

    function settle(address _vault, bytes32[] calldata _withdrawProof) external;

    function supply() external view returns (address);

    function transfer() external view returns (address);

    function vaultToPunk(address) external view returns (uint256);

    function withdrawCollateral(address _vault, address _to) external;

    function withdrawERC20(
        address _vault,
        address _to,
        address _token,
        uint256 _value,
        bytes32[] calldata _erc20TransferProof
    ) external;

    function withdrawERC721(
        address _vault,
        address _to,
        address _token,
        uint256 _tokenId,
        bytes32[] calldata _erc721TransferProof
    ) external;

    function withdrawERC1155(
        address _vault,
        address _to,
        address _token,
        uint256 _id,
        uint256 _value,
        bytes32[] calldata _erc1155TransferProof
    ) external;

    function withdrawEther(
        address _vault,
        address _to,
        bytes32[] calldata _ethTransferProof
    ) external;
}
