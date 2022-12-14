// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {InitInfo} from "../interfaces/IVault.sol";

/// @dev Interface for BaseVault protoform contract
interface IBaseVault {
    /// @dev Event to log deposit of ERC-20 tokens
    /// @param _from the sender depositing tokens
    /// @param _vault the vault depositing tokens into
    /// @param _tokens the addresses of the 1155 contracts
    /// @param _amounts the list of amounts being deposited
    event BatchDepositERC20(
        address indexed _from,
        address indexed _vault,
        address[] _tokens,
        uint256[] _amounts
    );

    /// @dev Event to log deposit of ERC-721 tokens
    /// @param _from the sender depositing tokens
    /// @param _vault the vault depositing tokens into
    /// @param _tokens the addresses of the 1155 contracts
    /// @param _ids the list of ids being deposited
    event BatchDepositERC721(
        address indexed _from,
        address indexed _vault,
        address[] _tokens,
        uint256[] _ids
    );

    /// @dev Event to log deposit of ERC-1155 tokens
    /// @param _from the sender depositing tokens
    /// @param _vault the vault depositing tokens into
    /// @param _tokens the addresses of the 1155 contracts
    /// @param _ids the list of ids being deposited
    /// @param _amounts the list of amounts being deposited
    event BatchDepositERC1155(
        address indexed _from,
        address indexed _vault,
        address[] _tokens,
        uint256[] _ids,
        uint256[] _amounts
    );

    function batchDepositERC20(
        address _to,
        address[] memory _tokens,
        uint256[] memory _amounts
    ) external;

    function batchDepositERC721(
        address _to,
        address[] memory _tokens,
        uint256[] memory _ids
    ) external;

    function batchDepositERC1155(
        address _to,
        address[] memory _tokens,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        bytes[] memory _datas
    ) external;

    function deployVault(address[] calldata _modules, InitInfo[] calldata _calls)
        external
        returns (address vault);

    function registry() external view returns (address);
}
