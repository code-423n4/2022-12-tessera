// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ICryptoPunk as IPunks} from "../interfaces/ICryptoPunk.sol";
import {IPunksMarketAdapter} from "../interfaces/IPunksMarketAdapter.sol";
import {IPunksMarketLister} from "../interfaces/IPunksMarketLister.sol";
import {IWrappedPunk as IWrapper} from "../interfaces/IWrappedPunk.sol";

/// @title PunksMarketLister
/// @author Tessera
/// @notice Target contract for executing listings on the Punks marketplace
contract PunksMarketLister is IPunksMarketLister {
    // @notice Address of the CryptoPunksMarket contract
    address public immutable punks;
    // @notice Address of the WrappedPunk contract
    address public immutable wrapper;

    // @dev Initializes punks and wrapper contracts
    constructor(address _punks, address _wrapper) {
        punks = _punks;
        wrapper = _wrapper;
    }

    /// @dev Callback for receiving Ether
    receive() external payable {}

    /// @notice Unwraps a native punk token
    /// @param _tokenId ID of the token
    function unwrap(uint256 _tokenId) external {
        IWrapper(wrapper).burn(_tokenId);
    }

    /// @notice Transfers punk to adapter
    /// @param _adapter Address of adapter contract
    /// @param _tokenId ID of the token
    function transferPunk(address _adapter, uint256 _tokenId) external {
        IPunks(punks).transferPunk(_adapter, _tokenId);
    }

    /// @notice Lists punk on marketplace through adapter
    /// @param _adapter Address of adapter contract
    /// @param _tokenId ID of the token
    /// @param _amount Amount being listed
    function list(
        address _adapter,
        uint256 _tokenId,
        uint256 _amount
    ) external {
        IPunksMarketAdapter(_adapter).list(_tokenId, _amount);
    }

    /// @notice Delists punk form marketplace through adapter
    /// @param _adapter Address of adapter contract
    /// @param _tokenId ID of the token
    function delist(address _adapter, uint256 _tokenId) external {
        IPunksMarketAdapter(_adapter).delist(_tokenId);
    }

    /// @notice Withdraws ether through adapter
    /// @param _adapter Address of adapter contract
    /// @param _to Address receiving ether
    function withdraw(address _adapter, address _to) external {
        IPunksMarketAdapter(_adapter).withdraw(_to);
    }
}
