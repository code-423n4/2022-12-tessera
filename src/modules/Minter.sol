// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Module} from "./Module.sol";
import {IMinter} from "../interfaces/IMinter.sol";
import {ISupply} from "../interfaces/ISupply.sol";
import {IVault} from "../interfaces/IVault.sol";
import {Permission} from "../interfaces/IVaultRegistry.sol";

/// @title Minter
/// @author Tessera
/// @notice Module contract for minting a fixed supply of Raes
contract Minter is IMinter, Module {
    /// @notice Address of Supply target contract
    address public immutable supply;

    /// @notice Initializes supply target contract
    constructor(address _supply) {
        supply = _supply;
    }

    /// @notice Gets the list of permissions installed on a vault
    /// @dev Permissions consist of a module contract, target contract, and function selector
    /// @return permissions A list of Permission Structs
    function getPermissions()
        public
        view
        virtual
        override(IMinter, Module)
        returns (Permission[] memory permissions)
    {
        permissions = new Permission[](1);
        permissions[0] = Permission(address(this), supply, ISupply.mint.selector);
    }

    /// @notice Mints a Rae supply
    /// @param _vault Address of the Vault
    /// @param _to Address of the receiver of Raes
    /// @param _raeSupply Number of NFT Raes minted to control the vault
    /// @param _mintProof List of proofs to execute a mint function
    function _mintRaes(
        address _vault,
        address _to,
        uint256 _raeSupply,
        bytes32[] memory _mintProof
    ) internal {
        bytes memory data = abi.encodeCall(ISupply.mint, (_to, _raeSupply));
        IVault(payable(_vault)).execute(supply, data, _mintProof);
    }
}
