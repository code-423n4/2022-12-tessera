// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ICryptoPunk as IPunks} from "../interfaces/ICryptoPunk.sol";
import {IPunksMarketAdapter} from "../interfaces/IPunksMarketAdapter.sol";

/// @title PunksMarketAdapter
/// @author Tessera
/// @notice Adapter contract for listing
contract PunksMarketAdapter is IPunksMarketAdapter {
    // @notice Address of the CryptoPunksMarket contract
    address public immutable punks;
    // @notice Address of the contract owner
    address public immutable vault;

    // @dev Initializes punks and vault contracts
    constructor(address _punks, address _vault) {
        punks = _punks;
        vault = _vault;
    }

    /// @dev Callback for receiving Ether
    receive() external payable {}

    /// @dev Modifier for restricting calls to contract owner
    modifier onlyOwner() {
        if (msg.sender != vault) revert NotAuthorized();
        _;
    }

    /// @notice Lists punk on marketplace
    /// @param _tokenId ID of the token
    /// @param _amount Amount being listed
    function list(uint256 _tokenId, uint256 _amount) external onlyOwner {
        IPunks(punks).offerPunkForSale(_tokenId, _amount);
    }

    /// @notice Delists punk from marketplace
    /// @param _tokenId ID of the token
    function delist(uint256 _tokenId) external onlyOwner {
        IPunks(punks).transferPunk(vault, _tokenId);
    }

    /// @notice Withdraws ether and transfers to module
    /// @param _to Address receiving ether
    function withdraw(address _to) external onlyOwner {
        uint256 amount = IPunks(punks).pendingWithdrawals(address(this));
        IPunks(punks).withdraw();
        payable(_to).transfer(amount);
    }
}
