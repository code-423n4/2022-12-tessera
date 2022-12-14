// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IIssuerFactory} from "../interfaces/IIssuerFactory.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IERC721} from "../interfaces/IERC721.sol";
import {IERC1155} from "../interfaces/IERC1155.sol";
import {IModule} from "../interfaces/IModule.sol";
import {IVaultRegistry, Permission} from "../interfaces/IVaultRegistry.sol";
import {MerkleBase} from "../utils/MerkleBase.sol";
import {Multicall} from "../utils/Multicall.sol";
import {Protoform} from "../protoforms/Protoform.sol";
import {InitInfo} from "../interfaces/IVault.sol";

contract IssuerFactory is IIssuerFactory, MerkleBase, Multicall, Protoform {
    address public registry;

    constructor(address _registry) {
        registry = _registry;
    }

    function deployVault(bytes calldata _data, address[] calldata _modules)
        external
        returns (address vault)
    {
        (address target, bytes memory data) = abi.decode(_data, (address, bytes));

        vault = _createVault(data, target, _modules);

        emit ActiveModules(vault, _modules);
    }

    function batchDepositERC20(
        address _to,
        address[] calldata _tokens,
        uint256[] calldata _amounts
    ) external {
        emit BatchDepositERC20(msg.sender, _to, _tokens, _amounts);
        for (uint256 i = 0; i < _tokens.length; ) {
            IERC20(_tokens[i]).transferFrom(msg.sender, _to, _amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    function batchDepositERC721(
        address _to,
        address[] calldata _tokens,
        uint256[] calldata _ids
    ) external {
        emit BatchDepositERC721(msg.sender, _to, _tokens, _ids);
        for (uint256 i = 0; i < _tokens.length; ) {
            IERC721(_tokens[i]).safeTransferFrom(msg.sender, _to, _ids[i]);
            unchecked {
                ++i;
            }
        }
    }

    function batchDepositERC1155(
        address _to,
        address[] calldata _tokens,
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        bytes[] calldata _datas
    ) external {
        emit BatchDepositERC1155(msg.sender, _to, _tokens, _ids, _amounts);
        unchecked {
            for (uint256 i = 0; i < _tokens.length; ++i) {
                IERC1155(_tokens[i]).safeTransferFrom(
                    msg.sender,
                    _to,
                    _ids[i],
                    _amounts[i],
                    _datas[i]
                );
            }
        }
    }

    function _createVault(
        bytes memory _data,
        address _target,
        address[] calldata _modules
    ) private returns (address vault) {
        (bytes32 _merkleRoot, bytes32[] memory _proof) = _merkleRootAndProof(_modules);

        InitInfo[] memory _calls = new InitInfo[](1);
        _calls[0] = InitInfo(_target, _data, _proof);

        vault = IVaultRegistry(registry).create(_merkleRoot, _calls);
    }

    function _merkleRootAndProof(address[] calldata _modules)
        private
        view
        returns (bytes32 merkleRoot, bytes32[] memory proof)
    {
        bytes32[] memory leafNodes = generateMerkleTree(_modules);
        merkleRoot = getRoot(leafNodes);
        proof = getProof(leafNodes, 0);
        delete leafNodes;
    }
}
