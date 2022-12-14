// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {InitInfo} from "./IVault.sol";

/// @dev Interface for IssuerFactory protoform contract
interface IIssuerFactory {
    event BatchDepositERC20(
        address indexed _from,
        address indexed _vault,
        address[] _tokens,
        uint256[] _amounts
    );

    event BatchDepositERC721(
        address indexed _from,
        address indexed _vault,
        address[] _tokens,
        uint256[] _ids
    );

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

    function deployVault(bytes calldata _data, address[] calldata _modules)
        external
        returns (address vault);

    function registry() external view returns (address);
}
