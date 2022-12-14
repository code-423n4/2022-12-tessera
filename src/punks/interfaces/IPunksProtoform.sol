// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @dev Interface for PunksProtoform contract
interface IPunksProtoform {
    function deployVault(
        uint256 _punkId,
        uint256 _totalSupply,
        address[] memory _modules,
        bytes32[] calldata _mintProof,
        bytes32[] calldata _unwrapProof
    ) external returns (address vault);

    function listing() external view returns (address);

    function registry() external view returns (address);

    function wrapper() external view returns (address);
}
