// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @dev Interface for CryptoPunksMarket contract
interface ICryptoPunk {
    function allInitialOwnersAssigned() external;

    function allPunksAssigned() external view returns (bool);

    function balanceOf(address) external view returns (uint256);

    function buyPunk(uint256 punkIndex) external payable;

    function getPunk(uint256 punkIndex) external;

    function offerPunkForSale(uint256 punkIndex, uint256 price) external;

    function owner() external view returns (address);

    function pendingWithdrawals(address) external view returns (uint256);

    function punkIndexToAddress(uint256) external view returns (address);

    function punkNoLongerForSale(uint256 punkIndex) external;

    function punksOfferedForSale(uint256)
        external
        view
        returns (
            bool isForSale,
            uint256 punkIndex,
            address seller,
            uint256 minValue,
            address onlySellTo
        );

    function setInitialOwner(address to, uint256 punkIndex) external;

    function transferPunk(address to, uint256 punkIndex) external;

    function withdraw() external;
}
