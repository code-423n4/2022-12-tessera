// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Module} from "../../modules/Module.sol";
import {Multicall} from "../../utils/Multicall.sol";
import {NFTReceiver} from "../../utils/NFTReceiver.sol";
import {PunksMarketAdapter} from "../utils/PunksMarketAdapter.sol";
import {PunksMarketLister} from "../targets/PunksMarketLister.sol";
import {SafeSend} from "../../utils/SafeSend.sol";
import {SelfPermit} from "../../utils/SelfPermit.sol";

import {ICryptoPunk as IPunks} from "../interfaces/ICryptoPunk.sol";
import {IERC1155} from "../../interfaces/IERC1155.sol";
import {IRae} from "../../interfaces/IRae.sol";
import {IOptimisticListingPunks, Listing} from "../interfaces/IOptimisticListingPunks.sol";
import {IPunksMarketLister} from "../interfaces/IPunksMarketLister.sol";
import {ISupply} from "../../interfaces/ISupply.sol";
import {ITransfer} from "../../interfaces/ITransfer.sol";
import {IVault} from "../../interfaces/IVault.sol";
import {IVaultRegistry, Permission} from "../../interfaces/IVaultRegistry.sol";

/// @title OptimisticListingPunks
/// @author Tessera
/// @notice Module contract for vaults to list CryptoPunks on their native Marketplace
contract OptimisticListingPunks is
    IOptimisticListingPunks,
    Module,
    Multicall,
    NFTReceiver,
    SafeSend,
    SelfPermit
{
    /// @notice Address of VaultRegistry contract
    address public immutable registry;
    /// @notice Address of Supply target contract
    address public immutable supply;
    /// @notice Address of Transfer target contract
    address public immutable transfer;
    /// @notice Address of the PunksMarketLister target contract
    address public immutable marketplace;
    /// @notice Address of the CryptoPunksMarket contract
    address public immutable punks;
    /// @notice Time period of proposed listing
    uint256 public immutable PROPOSAL_PERIOD;
    /// @notice Mapping of vault address to PunksMarketAdapter contract
    mapping(address => address) public adapters;
    /// @notice Mapping of vault address to punk token ID
    mapping(address => uint256) public vaultToPunk;
    /// @notice Mapping of vault address to active listings on the CryptoPunksMarket
    mapping(address => Listing) public activeListings;
    /// @notice Mapping of vault address to newly proposed listings
    mapping(address => Listing) public proposedListings;
    /// @notice Mapping of vault address to user address to collateral amount
    mapping(address => mapping(address => uint256)) public pendingBalances;

    /// @dev Modifier for punk owner to withdraw assets from the vault
    modifier onlyOwner(address _vault) {
        _verifyVault(_vault);
        // Reverts if caller is not owner of the punk
        if (IPunks(punks).punkIndexToAddress(vaultToPunk[_vault]) != msg.sender) revert NotOwner();
        _;
    }

    /// @dev Initializes registry, supply, transfer, marketplace and punks contracts
    constructor(
        address _registry,
        address _supply,
        address _transfer,
        address _marketplace,
        address _punks,
        uint256 _proposalPeriod,
        address payable _weth
    ) SafeSend(_weth) {
        registry = _registry;
        supply = _supply;
        transfer = _transfer;
        marketplace = _marketplace;
        punks = _punks;
        PROPOSAL_PERIOD = _proposalPeriod;
    }

    /// @dev Callback for receiving ether when the calldata is empty
    receive() external payable {}

    /// @notice Registers a vault and punk combo
    /// @dev Should only be called once per vault through the protoform
    /// @param _vault Address of the vault
    /// @param _punkId ID of the punk token
    /// @param _unwrapProof Merkle proof for unwrapping a native punk token
    function register(
        address _vault,
        uint256 _punkId,
        bytes32[] calldata _unwrapProof
    ) external {
        // Reverts if vault is not registered
        _verifyVault(_vault);
        // Reverts if vault is already registered with adapter contract
        if (adapters[_vault] != address(0)) revert AlreadyRegistered();

        // Deploys new PunksMarketAdapter contract
        adapters[_vault] = address(new PunksMarketAdapter(punks, _vault));

        // Initializes vault transaction for unwrap
        bytes memory data = abi.encodeCall(IPunksMarketLister.unwrap, (_punkId));
        // Executes the unwrapping of a native punk token by burning the WrappedPunk
        IVault(payable(_vault)).execute(marketplace, data, _unwrapProof);

        // Registers punk with vault
        vaultToPunk[_vault] = _punkId;

        // Initializes proposed and active listings to default
        proposedListings[_vault] = _defaultListing();
        activeListings[_vault] = _defaultListing();

        // Emits event for registering token with vault
        emit Register(_vault, _punkId);
    }

    /// @notice Proposes a new optimistic listing for a vault
    /// @param _vault Address of the vault
    /// @param _collateral Amount of tokens the proposer is risking
    /// @param _pricePerToken Desired listing price of the punk divided by total supply
    function propose(
        address _vault,
        uint256 _collateral,
        uint256 _pricePerToken
    ) external {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if vault is not owner of punk
        _verifyOwner(_vault);
        // Reverts if caller has insufficient token balance
        _verifyBalance(token, id, _collateral);
        // Reverts if price per token is not lower than both the proposed and active listings
        Listing memory proposedListing = proposedListings[_vault];
        if (
            _pricePerToken >= proposedListing.pricePerToken ||
            _pricePerToken >= activeListings[_vault].pricePerToken
        ) revert NotLower();

        // Sets the newly proposed listing
        proposedListings[_vault] = Listing(
            msg.sender,
            _collateral,
            _pricePerToken,
            block.timestamp
        );

        // Sets remaining collateral amount of proposer for withdrawal
        pendingBalances[_vault][proposedListing.proposer] += proposedListing.collateral;

        // Transfers new collateral amount from caller to this contract
        IERC1155(token).safeTransferFrom(msg.sender, address(this), id, _collateral, "");

        // Emits event for proposing new listing
        emit Propose(_vault, msg.sender, _collateral, _pricePerToken);
    }

    /// @notice Rejects a new listing proposal
    /// @param _vault Address of the vault
    /// @param _amount Amount of tokens being rejected
    function rejectProposal(address _vault, uint256 _amount) external payable {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if vault is not owner of punk
        _verifyOwner(_vault);
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
            proposedListings[_vault] = _defaultListing();
        }

        // Transfers tokens to caller
        IERC1155(token).safeTransferFrom(address(this), msg.sender, id, _amount, "");
        // Sends ether to proposer
        _sendEthOrWeth(proposer, msg.value);

        // Emits event for rejecting a proposed listing
        emit RejectProposal(_vault, msg.sender, _amount, msg.value);
    }

    /// @notice Rejects an active listing
    /// @param _vault Address of the vault
    /// @param _amount Amount of tokens being rejected
    /// @param _delistProof Merkle proof for delisting a punk
    function rejectActive(
        address _vault,
        uint256 _amount,
        bytes32[] calldata _delistProof
    ) external payable {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if vault is not owner of punk
        uint256 punkId = _verifyOwner(_vault);
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
            // Executes delisting of punk
            _delist(_vault, punkId, _delistProof);
            // Resets active listing to default
            activeListings[_vault] = _defaultListing();
            // Emits event for delisting punk
            emit Delist(_vault, punkId);
        }

        // Transfers tokens to caller
        IERC1155(token).safeTransferFrom(address(this), msg.sender, id, _amount, "");
        // Sends ether to proposer
        _sendEthOrWeth(proposer, msg.value);

        // Emits event for rejecting an active listing
        emit RejectActive(_vault, msg.sender, _amount, msg.value);
    }

    /// @notice Lists a punk for sale
    /// @param _vault Address of the vault
    /// @param _transferPunkProof Merkle proof for transferring punk
    /// @param _listProof Merkle proof for listing punk
    function list(
        address _vault,
        bytes32[] calldata _transferPunkProof,
        bytes32[] calldata _listProof
    ) external {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if vault is not owner of punk
        uint256 punkId = _verifyOwner(_vault);
        // Reverts if collateral of proposed listing has been rejected
        Listing memory proposedListing = proposedListings[_vault];
        if (proposedListing.collateral == 0) revert Rejected();
        // Reverts if proposal period has not elapsed
        if (proposedListing.proposalDate + PROPOSAL_PERIOD > block.timestamp)
            revert TimeNotElapsed();

        // Sets remaining collateral amount of proposer for withdrawal
        Listing memory activeListing = activeListings[_vault];
        pendingBalances[_vault][activeListing.proposer] = activeListing.collateral;

        // Replaces active listing with the successfully proposed listing
        activeListings[_vault] = proposedListing;
        // Resets proposed listing to default
        proposedListings[_vault] = _defaultListing();

        // Calculates new listing price
        uint256 newPrice = proposedListing.pricePerToken * IRae(token).totalSupply(id);

        // Transfers punk to adapter contract if vault is current owner
        if (IPunks(punks).punkIndexToAddress(punkId) == _vault) {
            // Initializes vault transaction for transferPunk
            bytes memory transferData = abi.encodeCall(
                IPunksMarketLister.transferPunk,
                (adapters[_vault], punkId)
            );
            // Executes transferring of punk to adapter contract
            IVault(payable(_vault)).execute(marketplace, transferData, _transferPunkProof);
        }

        // Initializes vault transaction for list
        bytes memory listData = abi.encodeCall(
            IPunksMarketLister.list,
            (adapters[_vault], punkId, newPrice)
        );
        // Executes listing of punk on CryptoPunksMarket
        IVault(payable(_vault)).execute(marketplace, listData, _listProof);

        // Emits event for successful listing
        emit List(_vault, punkId, newPrice);
    }

    /// @notice Cancels an active listing of a punk from being on sale
    /// @param _vault Address of the vault
    /// @param _delistProof Merkle proof for delisting a punk
    function cancel(address _vault, bytes32[] calldata _delistProof) external {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if vault is not owner of punk
        uint256 punkId = _verifyOwner(_vault);
        // Reverts if caller is not proposer of active listing
        Listing memory activeListing = activeListings[_vault];
        if (activeListing.proposer != msg.sender) revert NotProposer();

        // Resets active listing to default
        activeListings[_vault] = _defaultListing();

        // Executes delisting of punk from CryptoPunksMarket
        _delist(_vault, punkId, _delistProof);

        // Transfers remaining collateral amount to proposer
        IERC1155(token).safeTransferFrom(
            address(this),
            msg.sender,
            id,
            activeListing.collateral,
            ""
        );

        // Emits event for canceling a listing
        emit Cancel(_vault, punkId);
    }

    /// @notice Settles an active listing once a punk is sold
    /// @param _vault Address of the vault
    /// @param _withdrawProof Merkle proof for withdrawing pending payment after a sale
    function settle(address _vault, bytes32[] calldata _withdrawProof) external {
        // Reverts if vault is not registered
        _verifyVault(_vault);
        // Reverts if punk has not been sold
        uint256 punkId = _verifySale(_vault);
        // Reverts if active listing has already been settled
        Listing storage activeListing = activeListings[_vault];
        uint256 collateral = activeListing.collateral;
        if (collateral == 0) revert AlreadySettled();

        // Resets collateral amount
        activeListing.collateral = 0;

        // Sets remaining collateral amount of proposer for withdrawal
        pendingBalances[_vault][activeListing.proposer] = collateral;

        // Initializes vault transaction for withdraw
        bytes memory data = abi.encodeCall(
            IPunksMarketLister.withdraw,
            (adapters[_vault], address(this))
        );
        // Executes withdraw of ether from CryptoPunksMarket to this contract
        IVault(payable(_vault)).execute(marketplace, data, _withdrawProof);

        // Emits event for settling a vault
        emit Settle(_vault, punkId);
    }

    /// @notice Cashes out proceeds from the sale of an active listing
    /// @param _vault Address of the vault
    /// @param _burnProof Merkle proof for burning tokens
    function cash(address _vault, bytes32[] calldata _burnProof) external {
        // Reverts if vault is not registered
        (address token, uint256 id) = _verifyVault(_vault);
        // Reverts if punk has not been sold
        _verifySale(_vault);
        // Reverts if active listing has not been settled
        Listing memory activeListing = activeListings[_vault];
        if (activeListing.collateral != 0) revert NotSettled();
        // Reverts if token balance is insufficient
        // We use 1 as collateral to bypass the first check
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

    /// @notice Withdraws ether from a vault
    /// @param _vault Address of the vault
    /// @param _to Address of the receiver
    /// @param _ethTransferProof Merkle proof for transferring ether
    function withdrawEther(
        address _vault,
        address _to,
        bytes32[] calldata _ethTransferProof
    ) external onlyOwner(_vault) {
        bytes memory data = abi.encodeCall(ITransfer.ETHTransfer, (_to, _vault.balance));
        IVault(payable(_vault)).execute(transfer, data, _ethTransferProof);
    }

    /// @notice Withdraws an ERC-20 token from a vault
    /// @param _vault Address of the vault
    /// @param _to Address of the receiver
    /// @param _token Address of the token
    /// @param _value Transfer amount
    /// @param _erc20TransferProof Merkle proof for transferring an ERC-20 token
    function withdrawERC20(
        address _vault,
        address _to,
        address _token,
        uint256 _value,
        bytes32[] calldata _erc20TransferProof
    ) external onlyOwner(_vault) {
        bytes memory data = abi.encodeCall(ITransfer.ERC20Transfer, (_token, _to, _value));
        IVault(payable(_vault)).execute(transfer, data, _erc20TransferProof);
    }

    /// @notice Withdraws an ERC-721 token from a vault
    /// @param _vault Address of the vault
    /// @param _to Address of the receiver
    /// @param _token Address of the token
    /// @param _tokenId ID of the token
    /// @param _erc721TransferProof Merkle proof for transferring an ERC-721 token
    function withdrawERC721(
        address _vault,
        address _to,
        address _token,
        uint256 _tokenId,
        bytes32[] calldata _erc721TransferProof
    ) external onlyOwner(_vault) {
        bytes memory data = abi.encodeCall(
            ITransfer.ERC721TransferFrom,
            (_token, _vault, _to, _tokenId)
        );
        IVault(payable(_vault)).execute(transfer, data, _erc721TransferProof);
    }

    /// @notice Withdraws an ERC-1155 token from a vault
    /// @param _vault Address of the vault
    /// @param _to Address of the receiver
    /// @param _token Address of the token
    /// @param _id ID of the token type
    /// @param _value Transfer amount
    /// @param _erc1155TransferProof Merkle proof for transferring an ERC-1155 token
    function withdrawERC1155(
        address _vault,
        address _to,
        address _token,
        uint256 _id,
        uint256 _value,
        bytes32[] calldata _erc1155TransferProof
    ) external onlyOwner(_vault) {
        bytes memory data = abi.encodeCall(
            ITransfer.ERC1155TransferFrom,
            (_token, _vault, _to, _id, _value)
        );
        IVault(payable(_vault)).execute(transfer, data, _erc1155TransferProof);
    }

    /// @notice Gets the list of permissions installed on a vault
    /// @dev Permissions consist of a module contract, target contract, and function selector
    /// @return permissions List of vault permissions
    function getPermissions()
        public
        view
        override(IOptimisticListingPunks, Module)
        returns (Permission[] memory permissions)
    {
        permissions = new Permission[](10);
        // Burn function selector from supply contract
        permissions[0] = Permission(address(this), supply, ISupply.burn.selector);
        // Unwrap function selector from marketplace contract
        permissions[1] = Permission(address(this), marketplace, IPunksMarketLister.unwrap.selector);
        // List function selector from marketplace contract
        permissions[2] = Permission(
            address(this),
            marketplace,
            IPunksMarketLister.transferPunk.selector
        );
        // List function selector from marketplace contract
        permissions[3] = Permission(address(this), marketplace, IPunksMarketLister.list.selector);
        // Delist function selector from marketplace contract
        permissions[4] = Permission(address(this), marketplace, IPunksMarketLister.delist.selector);
        // Withdraw function selector from marketplace contract
        permissions[5] = Permission(
            address(this),
            marketplace,
            IPunksMarketLister.withdraw.selector
        );
        // ETHTransfer function selector from transfer contract
        permissions[6] = Permission(address(this), transfer, ITransfer.ETHTransfer.selector);
        // ERC20Transfer function selector from transfer contract
        permissions[7] = Permission(address(this), transfer, ITransfer.ERC20Transfer.selector);
        // ERC721TransferFrom function selector from transfer contract
        permissions[8] = Permission(address(this), transfer, ITransfer.ERC721TransferFrom.selector);
        // ERC1155TransferFrom function selector from transfer contract
        permissions[9] = Permission(
            address(this),
            transfer,
            ITransfer.ERC1155TransferFrom.selector
        );
    }

    /// @dev Executes the delisting of a punk from the marketplace
    function _delist(
        address _vault,
        uint256 _punkId,
        bytes32[] calldata _delistProof
    ) internal {
        bytes memory data = abi.encodeCall(IPunksMarketLister.delist, (adapters[_vault], _punkId));
        IVault(payable(_vault)).execute(marketplace, data, _delistProof);
    }

    /// @dev Returns the default listing
    function _defaultListing() internal view returns (Listing memory) {
        return Listing(address(this), 0, type(uint256).max, 0);
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

    /// @dev Reverts if vault or adapter is not owner of punk
    function _verifyOwner(address _vault) internal view returns (uint256 punkId) {
        punkId = vaultToPunk[_vault];
        address owner = IPunks(punks).punkIndexToAddress(punkId);
        if (owner != _vault && owner != adapters[_vault]) revert NotOwner();
    }

    /// @dev Reverts if punk has not been sold
    function _verifySale(address _vault) internal view returns (uint256 punkId) {
        punkId = vaultToPunk[_vault];
        if (IPunks(punks).punkIndexToAddress(punkId) == adapters[_vault]) revert NotSold();
    }

    /// @dev Reverts if vault is not registered
    function _verifyVault(address _vault) internal view returns (address token, uint256 id) {
        (token, id) = IVaultRegistry(registry).vaultToToken(_vault);
        if (id == 0) revert NotVault(_vault);
    }
}
