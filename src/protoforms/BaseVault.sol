// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {MerkleBase} from "../utils/MerkleBase.sol";
import {Multicall} from "../utils/Multicall.sol";
import {Protoform} from "../protoforms/Protoform.sol";

import {IBaseVault} from "../interfaces/IBaseVault.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IERC721} from "../interfaces/IERC721.sol";
import {IERC1155} from "../interfaces/IERC1155.sol";
import {InitInfo} from "../interfaces/IVault.sol";
import {ISupply} from "../interfaces/ISupply.sol";
import {IVaultRegistry} from "../interfaces/IVaultRegistry.sol";

/// @title BaseVault
/// @author Tessera
/// @notice Protoform contract for vault deployments with a fixed supply and buyout mechanism
contract BaseVault is IBaseVault, MerkleBase, Multicall, Protoform {
    /// @notice Address of VaultRegistry contract
    address public immutable registry;

    /// @notice Initializes registry and supply contracts
    /// @param _registry Address of the VaultRegistry contract
    constructor(address _registry) {
        registry = _registry;
    }

    /// @notice Deploys a new Vault and mints initial supply of Raes
    /// @param _modules The list of modules to be installed on the vault
    /// @param _calls List of initialization calls
    function deployVault(address[] calldata _modules, InitInfo[] calldata _calls)
        external
        returns (address vault)
    {
        bytes32[] memory leafNodes = generateMerkleTree(_modules);
        bytes32 merkleRoot = getRoot(leafNodes);
        vault = IVaultRegistry(registry).create(merkleRoot, _calls);
        emit ActiveModules(vault, _modules);
    }

    /// @notice Transfers ERC-20 tokens
    /// @param _to Target address
    /// @param _tokens[] Addresses of token contracts
    /// @param _amounts[] Transfer amounts
    function batchDepositERC20(
        address _to,
        address[] calldata _tokens,
        uint256[] calldata _amounts
    ) external {
        emit BatchDepositERC20(msg.sender, _to, _tokens, _amounts);
        for (uint256 i = 0; i < _tokens.length; ) {
            IERC20(_tokens[i]).transferFrom(msg.sender, _to, _amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Transfers ERC-721 tokens
    /// @param _to Target address
    /// @param _tokens[] Addresses of token contracts
    /// @param _ids[] IDs of the tokens
    function batchDepositERC721(
        address _to,
        address[] calldata _tokens,
        uint256[] calldata _ids
    ) external {
        emit BatchDepositERC721(msg.sender, _to, _tokens, _ids);
        for (uint256 i = 0; i < _tokens.length; ) {
            IERC721(_tokens[i]).safeTransferFrom(msg.sender, _to, _ids[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Transfers ERC-1155 tokens
    /// @param _to Target address
    /// @param _tokens[] Addresses of token contracts
    /// @param _ids[] Ids of the token types
    /// @param _amounts[] Transfer amounts
    /// @param _datas[] Additional transaction data
    function batchDepositERC1155(
        address _to,
        address[] calldata _tokens,
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        bytes[] calldata _datas
    ) external {
        emit BatchDepositERC1155(msg.sender, _to, _tokens, _ids, _amounts);
        unchecked {
            for (uint256 i = 0; i < _tokens.length; ++i) {
                IERC1155(_tokens[i]).safeTransferFrom(
                    msg.sender,
                    _to,
                    _ids[i],
                    _amounts[i],
                    _datas[i]
                );
            }
        }
    }
}
