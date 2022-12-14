// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @dev Interface for WrappedPunk contract
interface IWrappedPunk {
    function burn(uint256 punkIndex) external;

    function mint(uint256 punkIndex) external;

    function proxyInfo(address) external view returns (address);

    function punkContract() external view returns (address);

    function registerProxy() external;
}
