// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {MerkleBase} from "../../utils/MerkleBase.sol";
import {Minter} from "../../modules/Minter.sol";
import {Protoform} from "../../protoforms/Protoform.sol";

import {IERC721} from "../../interfaces/IERC721.sol";
import {IOptimisticListingPunks as IOptimistic} from "../interfaces/IOptimisticListingPunks.sol";
import {IPunksProtoform} from "../interfaces/IPunksProtoform.sol";
import {IVaultRegistry as IRegistry} from "../../interfaces/IVaultRegistry.sol";

/// @title PunksProtoform
/// @author Tessera
/// @notice Protoform contract for deploying new vaults with a fixed supply and distribution mechanism
contract PunksProtoform is IPunksProtoform, Minter, MerkleBase, Protoform {
    /// @notice Address of VaultRegistry contract
    address public immutable registry;
    /// @notice Address of WrappedPunk contract
    address public immutable wrapper;
    /// @notice Address of the OptimisticListingPunks contract
    address public immutable listing;

    /// @notice Initializes registry, wrapper and supply contracts
    /// @param _registry Address of the PunksRegistry contract
    /// @param _wrapper Address of the WrappedPunk contract
    /// @param _listing Address of the OptimisticListingPunks contract
    /// @param _supply Address of the Supply target contract
    constructor(
        address _registry,
        address _wrapper,
        address _listing,
        address _supply
    ) Minter(_supply) {
        registry = _registry;
        wrapper = _wrapper;
        listing = _listing;
    }

    /// @notice Deploys a new vault, transfers ownership of Punk token and mints rae supply
    /// @param _punkId Token ID of the CryptoPunk
    /// @param _totalSupply Total supply of raes minted
    /// @param _modules List of module contracts activated on the vault
    /// @param _mintProof Merkle proof for executing the minting of raes
    /// @param _unwrapProof Merkle proof for eecuting the unwrapping of a CryptoPunk token
    function deployVault(
        uint256 _punkId,
        uint256 _totalSupply,
        address[] memory _modules,
        bytes32[] calldata _mintProof,
        bytes32[] calldata _unwrapProof
    ) external returns (address vault) {
        vault = _create(_modules);
        _mint(vault, _punkId, _totalSupply, _mintProof);
        _register(vault, _punkId, _unwrapProof);
    }

    /// @dev Creates a new vault through the registry
    function _create(address[] memory _modules) internal returns (address vault) {
        bytes32[] memory leafNodes = generateMerkleTree(_modules);
        bytes32 merkleRoot = getRoot(leafNodes);
        vault = IRegistry(registry).create(merkleRoot);

        emit ActiveModules(vault, _modules);
    }

    /// @dev Transfers Wrapped Punk to vault and mints tokens to caller
    function _mint(
        address _vault,
        uint256 _punkId,
        uint256 _totalSupply,
        bytes32[] calldata _mintProof
    ) internal {
        IERC721(wrapper).safeTransferFrom(msg.sender, _vault, _punkId);

        _mintRaes(_vault, msg.sender, _totalSupply, _mintProof);
    }

    /// @dev Registers the vault with the punk token
    function _register(
        address _vault,
        uint256 _punkId,
        bytes32[] calldata _unwrapProof
    ) internal {
        IOptimistic(listing).register(_vault, _punkId, _unwrapProof);
    }
}
