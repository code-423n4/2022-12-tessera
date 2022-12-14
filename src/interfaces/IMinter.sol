// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Permission} from "./IVaultRegistry.sol";

/// @dev Interface for Minter module contract
interface IMinter {
    function getPermissions() external view returns (Permission[] memory permissions);

    function supply() external view returns (address);
}
