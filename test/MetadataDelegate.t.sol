// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./TestUtil.sol";
import "../src/utils/MetadataDelegate.sol";
import "openzeppelin-contracts/utils/Strings.sol";

contract MetadataDelegateTest is Test {
    MetadataDelegate public metadataDelegate;

    function setUp() public {
        metadataDelegate = new MetadataDelegate();
    }

    function testSetBaseURI() public {
        string memory uri = "https://api.tessera.co/raes/";
        metadataDelegate.setBaseURI(uri);
        assertEq(metadataDelegate.baseURI(), uri);
    }

    function testIdMetadata() public {
        string memory uri = "https://api.tessera.co/raes/";
        metadataDelegate.setBaseURI(uri);
        assertEq(
            metadataDelegate.tokenURI(1),
            string.concat(
                uri,
                Strings.toHexString(uint160(address(this)), 20),
                "/",
                Strings.toString(1)
            )
        );
    }

    function testContractMetadata() public {
        string memory uri = "https://api.tessera.co/raes/";
        metadataDelegate.setBaseURI(uri);
        assertEq(
            metadataDelegate.contractURI(),
            string.concat(uri, Strings.toHexString(uint160(address(this)), 20))
        );
    }
}
