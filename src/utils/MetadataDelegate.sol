// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "openzeppelin-contracts/utils/Strings.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "src/interfaces/IMetadataDelegate.sol";

contract MetadataDelegate is IMetadataDelegate, Ownable {
    using Strings for uint256;
    using Strings for uint160;
    string public baseURI;

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function tokenURI(uint256 _id) external view returns (string memory) {
        return string.concat(baseURI, uint160(msg.sender).toHexString(20), "/", _id.toString());
    }

    function contractURI() external view returns (string memory) {
        return string.concat(baseURI, uint160(msg.sender).toHexString(20));
    }
}
