// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.13;

import "./TestUtil.sol";

contract VaultFactoryTest is TestUtil {
    uint256 seed_1;
    uint256 seed_2;
    uint256 seed_3;
    address predicted_1;
    address predicted_2;
    address actual_1;
    address actual_2;

    function setUp() public {
        setUpContract();
    }

    function checkNextCreate2Helper(
        bytes32 merkleRoot,
        address owner,
        address origin
    ) public view returns (uint256, address) {
        bytes32 seed = IVaultFactory(factory).getNextSeed(origin);
        return (uint256(seed), IVaultFactory(factory).getNextAddress(origin, owner, merkleRoot));
    }

    function testDeploy() public {
        factory = registry.factory();
        (seed_1, predicted_1) = checkNextCreate2Helper(
            bytes32(0),
            address(0xBEEF),
            address(0xBEEF)
        );
        vm.startPrank(address(0xBEEF), address(0xBEEF));
        actual_1 = IVaultFactory(factory).deploy(bytes32(0));
        vm.stopPrank();
        (seed_2, ) = checkNextCreate2Helper(bytes32(0), address(0xBEEF), address(0xBEEF));
        assertEq(seed_2, seed_1 + 1);
        assertEq(predicted_1, actual_1);
    }

    function testDeploy(address who) public {
        factory = registry.factory();
        (seed_1, predicted_1) = checkNextCreate2Helper(bytes32(0), who, who);
        vm.startPrank(who, who);
        actual_1 = IVaultFactory(factory).deploy(bytes32(0));
        vm.stopPrank();
        (seed_2, predicted_2) = checkNextCreate2Helper(bytes32(0), who, who);
        vm.startPrank(who, who);
        actual_2 = IVaultFactory(factory).deploy(bytes32(0));
        vm.stopPrank();

        (seed_3, ) = checkNextCreate2Helper(bytes32(0), who, who);
        assertEq(seed_2, seed_1 + 1);
        assertEq(predicted_1, actual_1);
        assertEq(seed_3, seed_2 + 1);
        assertEq(predicted_2, actual_2);
    }

    function testDeployFor(address who) public {
        factory = registry.factory();
        (seed_1, predicted_1) = checkNextCreate2Helper(bytes32(0), who, who);
        vm.startPrank(who, who);
        actual_1 = IVaultFactory(factory).deployFor(bytes32(0), who);
        vm.stopPrank();
        (seed_2, predicted_2) = checkNextCreate2Helper(bytes32(0), who, who);
        vm.startPrank(who, who);
        actual_2 = IVaultFactory(factory).deployFor(bytes32(0), who);
        vm.stopPrank();

        (seed_3, ) = checkNextCreate2Helper(bytes32(0), who, who);
        assertEq(seed_2, seed_1 + 1);
        assertEq(predicted_1, actual_1);
        assertEq(seed_3, seed_2 + 1);
        assertEq(predicted_2, actual_2);
    }
}
