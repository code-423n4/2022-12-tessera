// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @dev Interface for PunksMarketAdapter contract
interface IPunksMarketAdapter {
    /// @dev Emitted when the caller is not the owner
    error NotAuthorized();

    function delist(uint256 _tokenId) external;

    function list(uint256 _tokenId, uint256 _amount) external;

    function punks() external view returns (address);

    function withdraw(address _to) external;
}
