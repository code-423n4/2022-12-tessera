// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Module} from "../../modules/Module.sol";
import {Multicall} from "../../utils/Multicall.sol";
import {NFTReceiver} from "../../utils/NFTReceiver.sol";
import {SafeSend} from "../../utils/SafeSend.sol";
import {SelfPermit} from "../../utils/SelfPermit.sol";

import {ConsiderationItem, ItemType, OfferItem, Order, OrderParameters, OrderComponents, OrderType} from "seaport/lib/ConsiderationStructs.sol";
import {ConsiderationInterface as ISeaport} from "seaport/interfaces/ConsiderationInterface.sol";
import {IERC1155} from "../../interfaces/IERC1155.sol";
import {IOptimisticListingSeaport, Listing} from "../interfaces/IOptimisticListingSeaport.sol";
import {IRae} from "../../interfaces/IRae.sol";
import {ISeaportLister} from "../interfaces/ISeaportLister.sol";
import {ISupply} from "../../interfaces/ISupply.sol";
import {IVault} from "../../interfaces/IVault.sol";
import {IVaultRegistry, Permission} from "../../interfaces/IVaultRegistry.sol";

/// @title OptimisticListingSeaport
/// @author Tessera
/// @notice Module contract for listing vault assets through the Seaport protocol
contract OptimisticListingSeaport is
    IOptimisticListingSeaport,
    Module,
    Multicall,
    NFTReceiver,
    SafeSend,
    SelfPermit
{
    /// @notice Address of VaultRegistry contract
    address public immutable registry;
    /// @notice Address of the Seaport contract
    address public immutable seaport;
    /// @notice Address of the Zone to list items under
    address public immutable zone;
    /// @notice The conduit key used to deploy the conduit
    bytes32 public immutable conduitKey;
    /// @notice Address of Supply target contract
    address public immutable supply;
    /// @notice Address of the SeaportLister target contract
    address public immutable seaportLister;
    /// @notice Time period of a proposed listing
    uint256 public immutable PROPOSAL_PERIOD;
    /// @notice Address of the OpenSea recipient for receiving fees
    address payable public immutable OPENSEA_RECIPIENT;
    /// @notice Address of the protocol fee receiver
    address payable public feeReceiver;
    /// @notice Mapping of vault address to order hash
    mapping(address => bytes32) public vaultOrderHash;
    /// @notice Mapping of vault address to active listings on Seaport
    mapping(address => Listing) public activeListings;
    /// @notice Mapping of vault address to newly proposed listings
    mapping(address => Listing) public proposedListings;
    /// @notice Mapping of vault address to user address to collateral amount
    mapping(address => mapping(address => uint256)) public pendingBalances;

    /// @dev Initializes contract state
    constructor(
        address _registry,
        address _seaport,
        address _zone,
        bytes32 _conduitKey,
        address _supply,
        address _seaportLister,
        address payable _feeReceiver,
        address payable _openseaRecipient,
        uint256 _proposalPeriod,
        address payable _weth
    ) SafeSend(_weth) {
        registry = _registry;
        seaport = _seaport;
        zone = _zone;
        conduitKey = _conduitKey;
        supply = _supply;
        seaportLister = _seaportLister;
        feeReceiver = _feeReceiver;
        OPENSEA_RECIPIENT = _openseaRecipient;
        PROPOSAL_PERIOD = _proposalPeriod;
    }

    /// @dev Callback for receiving ether when the calldata is empty
    receive() external payable {}

    /// @notice Proposes a new optimistic listing for a vault
    /// @param _vault Address of the vault
    /// @param _collateral Amount of tokens the proposer is risking
    /// @param _pricePerToken Desired listing price of the vault assets divided by total supply
    /// @param _offer List of items included in the offer to be listed
    function propose(
        address _vault,
        uint256 _collateral,
        uint256 _pricePerToken,
        OfferItem[] calldata _offer
    ) external {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if vault is not current owner of the assets
        if (_verifySale(_vault)) revert NotOwner();
        // Reverts if caller has insufficient token balance
        _verifyBalance(token, id, _collateral);
        // Initializes the mappings if this is the first time a proposal is being submitted for the vault
        Listing storage proposedListing = proposedListings[_vault];
        Listing storage activeListing = activeListings[_vault];
        if (
            proposedListings[_vault].proposer == address(0) &&
            activeListings[_vault].proposer == address(0)
        ) {
            _setListing(proposedListing, address(this), 0, type(uint256).max, 0);
            _setListing(activeListing, address(this), 0, type(uint256).max, 0);
        }
        // Reverts if price per token is not lower than both the proposed and active listings
        if (
            _pricePerToken >= proposedListing.pricePerToken ||
            _pricePerToken >= activeListings[_vault].pricePerToken
        ) revert NotLower();

        // Calculates listing price based on price per token and total supply of Raes
        uint256 listingPrice = _pricePerToken * IRae(token).totalSupply(id);

        // Constructs Seaport order and sets the proposed listing
        _constructOrder(_vault, listingPrice, _offer);
        _setListing(proposedListing, msg.sender, _collateral, _pricePerToken, block.timestamp);

        // Sets collateral amount to pending balances for withdrawal
        pendingBalances[_vault][proposedListing.proposer] += proposedListing.collateral;

        // Transfers new collateral amount from caller to this contract
        IERC1155(token).safeTransferFrom(msg.sender, address(this), id, _collateral, "");

        // Emits event for proposing new listing
        emit Propose(_vault, msg.sender, _collateral, _pricePerToken, proposedListing.order);
    }

    /// @notice Rejects a new listing proposal
    /// @param _vault Address of the vault
    /// @param _amount Amount of tokens being rejected
    function rejectProposal(address _vault, uint256 _amount) external payable {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if vault is not current owner of the assets
        if (_verifySale(_vault)) revert NotOwner();
        // Reverts if collateral is less than amount of rejected tokens
        Listing storage proposedListing = proposedListings[_vault];
        if (proposedListing.collateral < _amount) revert InsufficientCollateral();
        // Reverts if payment amount is incorrect
        if (proposedListing.pricePerToken * _amount != msg.value) revert InvalidPayment();

        // Store proposer in memory
        address proposer = proposedListing.proposer;

        // Decrements collateral amount
        proposedListing.collateral -= _amount;

        // Checks if proposed listing has been rejected
        if (proposedListing.collateral == 0) {
            // Resets proposed listing to default
            _setListing(proposedListing, address(this), 0, type(uint256).max, 0);
        }

        // Transfers tokens to caller
        IERC1155(token).safeTransferFrom(address(this), msg.sender, id, _amount, "");
        // Sends ether to proposer
        _sendEthOrWeth(proposer, msg.value);

        // Emits event for rejecting a proposed listing
        emit RejectProposal(_vault, msg.sender, _amount, msg.value, proposedListing.order);
    }

    /// @notice Rejects an active listing
    /// @param _vault Address of the vault
    /// @param _amount Amount of tokens being rejected
    /// @param _delistProof Merkle proof for executing the delisting of assets
    function rejectActive(
        address _vault,
        uint256 _amount,
        bytes32[] calldata _delistProof
    ) external payable {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if vault is not current owner of the assets
        if (_verifySale(_vault)) revert NotOwner();
        // Reverts if collateral is less than amount of rejected tokens
        Listing storage activeListing = activeListings[_vault];
        if (activeListing.collateral < _amount) revert InsufficientCollateral();
        // Reverts if payment amount is incorrect
        if (activeListing.pricePerToken * _amount != msg.value) revert InvalidPayment();

        // Store proposer in memory
        address proposer = activeListing.proposer;

        // Decrements collateral amount
        activeListing.collateral -= _amount;

        // Checks if active listing has been rejected
        if (activeListing.collateral == 0) {
            // Cancels the Seaport Order
            _delist(_vault, _delistProof);
            // Resets active listing to default
            delete activeListings[_vault];
            _setListing(activeListing, address(this), 0, type(uint256).max, 0);
            // Emits event for delisting assets
            emit Delist(_vault, activeListing.order);
        }

        // Transfers tokens to caller
        IERC1155(token).safeTransferFrom(address(this), msg.sender, id, _amount, "");
        // Sends ether to proposer
        _sendEthOrWeth(proposer, msg.value);

        // Emits event for rejecting an active listing
        emit RejectActive(_vault, msg.sender, _amount, msg.value, activeListing.order);
    }

    /// @notice Lists the assets for sale
    /// @param _vault Address of the vault
    /// @param _listProof Merkle proof for executing the listing of assets
    function list(address _vault, bytes32[] calldata _listProof) public {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if vault is not current owner of the assets
        if (_verifySale(_vault)) revert NotOwner();
        // Reverts if collateral of proposed listing has been rejected
        Listing storage proposedListing = proposedListings[_vault];
        if (proposedListing.collateral == 0) revert Rejected();
        // Reverts if proposal period has not elapsed
        if (proposedListing.proposalDate + PROPOSAL_PERIOD > block.timestamp)
            revert TimeNotElapsed();

        // Sets remaining collateral amount of proposer for withdrawal
        Listing memory activeListing = activeListings[_vault];
        pendingBalances[_vault][activeListing.proposer] = activeListing.collateral;

        // Calculates new listing price
        uint256 newPrice = proposedListing.pricePerToken * IRae(token).totalSupply(id);

        // Structures the order array
        Order[] memory order = new Order[](1);
        order[0] = proposedListing.order;

        // Replaces active listing with the successfully proposed listing
        activeListings[_vault] = proposedListing;
        // Resets proposed listing to default
        _setListing(proposedListing, address(this), 0, type(uint256).max, 0);

        // List order on Seaport
        bytes memory data = abi.encodeCall(ISeaportLister.validateListing, (seaport, order));
        IVault(payable(_vault)).execute(seaportLister, data, _listProof);

        // Emits event for successful listing
        emit List(_vault, newPrice, activeListings[_vault].order);
    }

    /// @notice Cancels an active listing from being on sale
    /// @param _vault Address of the vault
    /// @param _delistProof Merkle proof for executing the delisting of assets
    function cancel(address _vault, bytes32[] calldata _delistProof) external {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if vault is not current owner of the assets
        if (_verifySale(_vault)) revert NotOwner();
        // Reverts if caller is not proposer of active listing
        Listing storage activeListing = activeListings[_vault];
        if (activeListing.proposer != msg.sender) revert NotProposer();

        // Cancels the Seaport Order
        _delist(_vault, _delistProof);

        uint256 collateral = activeListing.collateral;
        // Resets active listing to default
        _setListing(activeListing, address(this), 0, type(uint256).max, 0);

        // Transfers remaining collateral amount to proposer
        IERC1155(token).safeTransferFrom(address(this), msg.sender, id, collateral, "");

        // Emits event for canceling a listing
        emit Cancel(_vault, activeListing.order);
    }

    /// @notice Cashes out proceeds from the sale of an active listing
    /// @param _vault Address of the vault
    /// @param _burnProof Merkle proof for executing the burning of Raes
    function cash(address _vault, bytes32[] calldata _burnProof) external {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if active listing has not been settled
        Listing storage activeListing = activeListings[_vault];
        // Reverts if listing has not been sold
        if (!_verifySale(_vault)) {
            revert NotSold();
        } else if (activeListing.collateral != 0) {
            uint256 collateral = activeListing.collateral;
            activeListing.collateral = 0;
            // Sets collateral amount to pending balances for withdrawal
            pendingBalances[_vault][activeListing.proposer] = collateral;
        }
        // Reverts if token balance is insufficient
        uint256 tokenBalance = _verifyBalance(token, id, 1);
        // Calculates ether payment for withdrawal
        uint256 payment = tokenBalance * activeListing.pricePerToken;

        // Initializes vault transaction for burn
        bytes memory data = abi.encodeCall(ISupply.burn, (msg.sender, tokenBalance));
        // Executes burn of tokens from caller
        IVault(payable(_vault)).execute(supply, data, _burnProof);

        // Transfers payment to token holder
        _sendEthOrWeth(msg.sender, payment);

        // Emits event for cashing out of listing
        emit Cash(_vault, msg.sender, payment);
    }

    /// @notice Withdraws pending collateral balance to given address
    /// @param _vault Address of the vault
    /// @param _to Address of the receiver
    function withdrawCollateral(address _vault, address _to) external {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if token balance is insufficient
        uint256 balance = pendingBalances[_vault][_to];
        if (balance == 0) revert NotEnoughTokens();

        // Resets collateral balance amount
        pendingBalances[_vault][_to] = 0;

        // Transfers collateral amount to receiver
        IERC1155(token).safeTransferFrom(address(this), _to, id, balance, "");

        // Emits event for withdrawing collateral balance
        emit WithdrawCollateral(_vault, _to, balance);
    }

    /// @notice Sets the feeReceiver address
    /// @param _new The new fee receiver address
    function updateFeeReceiver(address payable _new) external {
        if (msg.sender != feeReceiver) revert NotAuthorized();
        feeReceiver = _new;
    }

    /// @notice Gets the list of permissions installed on a vault
    /// @dev Permissions consist of a module contract, target contract, and function selector
    /// @return permissions List of vault permissions
    function getPermissions()
        public
        view
        override(IOptimisticListingSeaport, Module)
        returns (Permission[] memory permissions)
    {
        permissions = new Permission[](3);
        // burn function selector from supply contract
        permissions[0] = Permission(address(this), supply, ISupply.burn.selector);
        // unwrap function selector from marketplace contract
        permissions[1] = Permission(
            address(this),
            seaportLister,
            ISeaportLister.validateListing.selector
        );
        // list function selector from marketplace contract
        permissions[2] = Permission(
            address(this),
            seaportLister,
            ISeaportLister.cancelListing.selector
        );
    }

    /// @dev Constructs a seaport order given an OfferItem and a price per token
    function _constructOrder(
        address _vault,
        uint256 _listingPrice,
        OfferItem[] calldata _offer
    ) internal {
        Order storage order = proposedListings[_vault].order;
        OrderParameters storage orderParams = order.parameters;
        {
            orderParams.offerer = _vault;
            orderParams.startTime = block.timestamp;
            // order doesn't expire in human time scales and needs explicit cancellations
            orderParams.endTime = type(uint256).max;
            orderParams.zone = zone;
            // 0: no partial fills, anyone can execute
            orderParams.orderType = OrderType.FULL_OPEN;
            orderParams.conduitKey = conduitKey;
            // 1 Consideration for the listing itself + 1 consideration for the fees
            orderParams.totalOriginalConsiderationItems = 3;
        }

        // Builds the order params from the offer items
        unchecked {
            for (uint256 i = 0; i < _offer.length; ++i) {
                orderParams.offer.push(_offer[i]);
            }
        }

        uint256 openseaFees = _listingPrice / 40;
        uint256 tesseraFees = _listingPrice / 20;

        // Attaches the actual consideration of the order
        orderParams.consideration.push(
            ConsiderationItem(
                ItemType.NATIVE,
                address(0),
                0,
                _listingPrice,
                _listingPrice,
                payable(address(this))
            )
        );

        // Attaches a payment to the fee receiver to the consideration
        orderParams.consideration.push(
            ConsiderationItem(
                ItemType.NATIVE,
                address(0),
                0,
                openseaFees,
                openseaFees,
                OPENSEA_RECIPIENT
            )
        );

        // Attaches a payment to the fee receiver to the consideration
        orderParams.consideration.push(
            ConsiderationItem(ItemType.NATIVE, address(0), 0, tesseraFees, tesseraFees, feeReceiver)
        );

        uint256 counter = ISeaport(seaport).getCounter(_vault);
        vaultOrderHash[_vault] = _getOrderHash(orderParams, counter);
    }

    /// @dev Executes the delisting of the assets from the marketplace
    function _delist(address _vault, bytes32[] calldata _delistProof) internal {
        OrderParameters memory orderParams = activeListings[_vault].order.parameters;

        // Gets order components for a vaults order
        uint256 totalConsiderationItems = orderParams.totalOriginalConsiderationItems;
        orderParams.totalOriginalConsiderationItems = 0;
        OrderComponents memory orderComps;
        assembly {
            orderComps := orderParams
        }
        OrderComponents[] memory components = new OrderComponents[](1);
        components[0] = orderComps;

        // Cancels the Seaport listing
        bytes memory data = abi.encodeCall(ISeaportLister.cancelListing, (seaport, components));
        IVault(payable(_vault)).execute(seaportLister, data, _delistProof);

        // Restores order parameters
        orderParams.totalOriginalConsiderationItems = totalConsiderationItems;
    }

    /// @dev Reverts if token balance is insufficient
    function _verifyBalance(
        address _token,
        uint256 _id,
        uint256 _collateral
    ) internal view returns (uint256 tokenBalance) {
        tokenBalance = IERC1155(_token).balanceOf(msg.sender, _id);
        if (_collateral == 0 || tokenBalance < _collateral) revert NotEnoughTokens();
    }

    /// @dev Reverts if vault is not current owner of the assets
    function _verifySale(address _vault) internal view returns (bool status) {
        (bool isValidated, bool isCancelled, uint256 totalFilled, uint256 totalSize) = ISeaport(
            seaport
        ).getOrderStatus(vaultOrderHash[_vault]);

        if (isValidated && !isCancelled && totalFilled > 0 && totalFilled == totalSize) {
            status = true;
        }
    }

    /// @dev Reverts if vault is not registered
    function _verifyVault(address _vault) internal view returns (address token, uint256 id) {
        (token, id) = IVaultRegistry(registry).vaultToToken(_vault);
        if (id == 0) revert NotVault(_vault);
    }

    /// @dev Generates the order hash from the order components
    function _getOrderHash(OrderParameters memory _orderParams, uint256 _counter)
        internal
        view
        returns (bytes32 orderHash)
    {
        OrderComponents memory orderComps = OrderComponents(
            _orderParams.offerer,
            _orderParams.zone,
            _orderParams.offer,
            _orderParams.consideration,
            _orderParams.orderType,
            _orderParams.startTime,
            _orderParams.endTime,
            _orderParams.zoneHash,
            _orderParams.salt,
            _orderParams.conduitKey,
            _counter
        );
        orderHash = ISeaport(seaport).getOrderHash(orderComps);
    }

    /// @dev Sets a proposed or active listing in storage
    function _setListing(
        Listing storage _listing,
        address _proposer,
        uint256 _collateral,
        uint256 _pricePerToken,
        uint256 _proposalDate
    ) internal {
        _listing.proposer = _proposer;
        _listing.collateral = _collateral;
        _listing.pricePerToken = _pricePerToken;
        _listing.proposalDate = _proposalDate;
    }
}
