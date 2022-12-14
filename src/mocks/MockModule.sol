// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../interfaces/IModule.sol";
import {Permission} from "../interfaces/IVaultRegistry.sol";

contract MockModule is IModule {
    function getPermissions() external pure returns (Permission[] memory permissions) {
        permissions = new Permission[](1);
        permissions[0] = Permission(address(1), address(1), 0x0);
    }

    function getLeaves() external pure returns (bytes32[] memory nodes) {
        nodes = new bytes32[](1);
        Permission[] memory permissions = new Permission[](1);
        permissions[0] = Permission(address(1), address(1), 0x0);
        nodes[0] = keccak256(abi.encode(permissions[0]));
    }

    function getUnhashedLeaves() external pure returns (bytes[] memory nodes) {}
}
