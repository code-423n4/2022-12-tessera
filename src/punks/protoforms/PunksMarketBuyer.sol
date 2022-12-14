// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Protoform} from "../../protoforms/Protoform.sol";

import {ICryptoPunk} from "../interfaces/ICryptoPunk.sol";
import {IERC721} from "../../interfaces/IERC721.sol";
import {IPunksMarketBuyer} from "../interfaces/IPunksMarketBuyer.sol";
import {IOptimisticListingPunks} from "../interfaces/IOptimisticListingPunks.sol";
import {IVaultRegistry} from "../../interfaces/IVaultRegistry.sol";
import {IWrappedPunk} from "../interfaces/IWrappedPunk.sol";

/// @title PunksMarketBuyer
/// @author Tessera
/// @notice Protoform contract for executing CryptoPunk purchase orders and deploying vaults
contract PunksMarketBuyer is IPunksMarketBuyer, Protoform {
    /// @notice Address of the VaultRegistry
    address public immutable registry;
    /// @notice Address of the WrappedPunk contract
    address public immutable wrapper;
    /// @notice Address of the WrappedPunk proxy contract
    address public immutable proxy;
    /// @notice Address of the OptimisticListingPunks module contract
    address public immutable listing;

    /// @dev Initializes contracts and registers wrapper proxy
    constructor(
        address _registry,
        address _wrapper,
        address _listing
    ) {
        registry = _registry;
        wrapper = _wrapper;
        listing = _listing;

        IWrappedPunk(wrapper).registerProxy();
        proxy = IWrappedPunk(wrapper).proxyInfo(address(this));
    }

    /// @dev Fallback for receiving either when calldata is empty
    receive() external payable {}

    /// @notice Executes an arbitrary purchase order for a CryptoPunk
    /// @param _order Bytes value of the necessary order parameters
    /// return vault Address of the deployed vault
    function execute(bytes memory _order) external payable returns (address vault) {
        // Decodes punks contract and tokenId from purchase order data
        (address punks, uint256 tokenId) = abi.decode(_order, (address, uint256));

        // Purchases punk from CryptoPunksMarket contract
        ICryptoPunk(payable(punks)).buyPunk{value: msg.value}(tokenId);

        // Transfers punk to proxy
        ICryptoPunk(punks).transferPunk(proxy, tokenId);

        // Mints wrapped punk
        IWrappedPunk(wrapper).mint(tokenId);

        // Deploys new vault with set permissions
        bytes32[] memory unwrapProof;
        (vault, unwrapProof) = _deployVault(tokenId);

        // Transfers wrapped punk from this contract to vault
        IERC721(wrapper).safeTransferFrom(address(this), vault, tokenId);

        // Registers vault with punk on OptimisticListingPunks module
        IOptimisticListingPunks(listing).register(vault, tokenId, unwrapProof);
    }

    /// @dev Deploys new vault with set permissions
    function _deployVault(uint256 _punkId)
        internal
        returns (address vault, bytes32[] memory unwrapProof)
    {
        // Builds list of modules to activate on the vault
        address[] memory modules = new address[](2);
        modules[0] = msg.sender;
        modules[1] = listing;

        // Generates merkle tree and root from list of modules
        bytes32[] memory leafNodes = generateMerkleTree(modules);
        bytes32 merkleRoot = getRoot(leafNodes);

        // Generates merkle proof of leaf node at index 2 for unwrapping punk
        unwrapProof = getProof(leafNodes, 2);

        // Creates new vault with predetermined modules
        vault = IVaultRegistry(registry).create(merkleRoot);

        // Emits event for modules activated on the vault
        emit ActiveModules(vault, modules);
    }
}
