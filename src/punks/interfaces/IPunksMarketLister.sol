// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @dev Interface for PunksMarketLister target contract
interface IPunksMarketLister {
    function delist(address _adapter, uint256 _tokenId) external;

    function list(
        address _adapter,
        uint256 _tokenId,
        uint256 _amount
    ) external;

    function punks() external view returns (address);

    function transferPunk(address _adapter, uint256 _tokenId) external;

    function unwrap(uint256 _tokenId) external;

    function withdraw(address _adapter, address _to) external;

    function wrapper() external view returns (address);
}
