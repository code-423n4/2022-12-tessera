// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.13;

import "./PunksTestUtil.t.sol";

// USER ROLES
// Deployer: PunksProtoformTest => address(this)
// Vaulter: Alice => address(111)
contract PunksProtoformTest is PunksTestUtil {
    // Errors
    bytes ERC721_APPROVAL_ERROR = bytes("ERC721: transfer caller is not owner nor approved");

    /// =================
    /// ===== SETUP =====
    /// =================
    function setUp() public {
        // base
        _setUpContract();
        _setUpProof();
        // punks
        _setOwner(address(this), alice, punkId);
        _setAssigned(address(this));
        // wrapper
        _registerProxy(alice);
        _transferPunk(alice, proxy, punkId);
        _wrapPunk(alice, punkId);

        vm.label(address(this), "PunksProtoformTest");
    }

    /// ========================
    /// ===== DEPLOY VAULT =====
    /// ========================
    function testDeployVault() public {
        // setup
        _setWrapperApproval(alice, address(protoform), true);
        // execute
        _deployVault(alice, punkId, mintProof, unwrapProof);
        // expect
        _assertPunkOwner(vault, punkId);
        _assertTokenBalance(alice, token, id, TOTAL_SUPPLY);
    }

    function testDeployVaultRevertNoApproval() public {
        // setup
        _setWrapperApproval(alice, address(protoform), false);
        // expect
        vm.expectRevert(ERC721_APPROVAL_ERROR);
        // execute
        _deployVault(alice, punkId, mintProof, unwrapProof);
    }

    function testDeployVaultRevertInvalidProof() public {
        // setup
        _setWrapperApproval(alice, address(protoform), true);
        // expect
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.NotAuthorized.selector,
                address(protoform),
                address(supply),
                ISupply.mint.selector
            )
        );
        // execute
        _deployVault(alice, punkId, unwrapProof, mintProof);
    }
}
