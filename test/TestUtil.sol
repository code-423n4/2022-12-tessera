// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import {Rae} from "../src/Rae.sol";
import {BaseVault} from "../src/protoforms/BaseVault.sol";
import {Minter} from "../src/modules/Minter.sol";
import {MockModule} from "../src/mocks/MockModule.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {MockERC1155} from "../src/mocks/MockERC1155.sol";
import {NFTReceiver} from "../src/utils/NFTReceiver.sol";
import {Supply, ISupply} from "../src/targets/Supply.sol";
import {Transfer} from "../src/targets/Transfer.sol";
import {TransferReference} from "../src/references/TransferReference.sol";
import {Vault} from "../src/Vault.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {VaultRegistry} from "../src/VaultRegistry.sol";
import {WETH} from "@rari-capital/solmate/src/tokens/WETH.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IERC721} from "../src/interfaces/IERC721.sol";
import {IERC1155} from "../src/interfaces/IERC1155.sol";
import {IRae} from "../src/interfaces/IRae.sol";
import {IModule} from "../src/interfaces/IModule.sol";
import {IVault, InitInfo} from "../src/interfaces/IVault.sol";
import {IVaultFactory} from "../src/interfaces/IVaultFactory.sol";
import {IVaultRegistry} from "../src/interfaces/IVaultRegistry.sol";
import "../src/constants/Permit.sol";

contract TestUtil is Test {
    BaseVault public baseVault;
    Minter public minter;
    MockModule public mockModule;
    NFTReceiver public receiver;
    Supply public supplyTarget;
    Transfer public transferTarget;
    Vault public vaultProxy;
    VaultRegistry public registry;
    WETH public weth;

    address public alice;
    address public bob;
    address public eve;

    mapping(address => uint256) public pkey;

    address public buyout;
    address public erc20;
    address public erc721;
    address public erc1155;
    address public factory;
    address public token;
    address public vault;
    bool public approved;
    uint256 public deadline;
    uint256 public nonce;
    uint256 public proposalPeriod;
    uint256 public rejectionPeriod;
    uint256 public tokenId;

    address[] public modules;

    bytes32 public merkleRoot;
    bytes32[] public merkleTree;
    bytes32[] public mintProof;
    bytes32[] public burnProof;
    bytes32[] public erc20TransferProof;
    bytes32[] public erc721TransferProof;
    bytes32[] public erc1155TransferProof;
    bytes32[] public erc1155BatchTransferProof;

    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant TOTAL_SUPPLY = 10000;
    uint256 public constant HALF_SUPPLY = TOTAL_SUPPLY / 2;
    address public constant WETH_ADDRESS = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant FEES = address(0xE626d419Dd60BE8038C46381ad171A0b3d22ed25);

    /// ==================
    /// ===== SETUPS =====
    /// ==================
    function setUpContract() public virtual {
        weth = new WETH();
        registry = new VaultRegistry();
        supplyTarget = new Supply(address(registry));
        minter = new Minter(address(supplyTarget));
        transferTarget = new Transfer();
        receiver = new NFTReceiver();
        baseVault = new BaseVault(address(registry));
        erc20 = address(new MockERC20());
        erc721 = address(new MockERC721());
        erc1155 = address(new MockERC1155());

        vm.label(address(registry), "VaultRegistry");
        vm.label(address(supplyTarget), "SupplyTarget");
        vm.label(address(transferTarget), "TransferTarget");
        vm.label(address(baseVault), "BaseVault");
        vm.label(address(erc20), "ERC20");
        vm.label(address(erc721), "ERC721");
        vm.label(address(erc1155), "ERC1155");
        vm.label(address(weth), "WETH");
    }

    function setUpProof() public virtual {
        modules = new address[](1);
        modules[0] = address(baseVault);

        merkleTree = baseVault.generateMerkleTree(modules);
        merkleRoot = baseVault.getRoot(merkleTree);
        burnProof = baseVault.getProof(merkleTree, 0);
        erc20TransferProof = baseVault.getProof(merkleTree, 1);
        erc721TransferProof = baseVault.getProof(merkleTree, 2);
        erc1155TransferProof = baseVault.getProof(merkleTree, 3);
        erc1155BatchTransferProof = baseVault.getProof(merkleTree, 4);
    }

    function setUpUser(uint256 _privateKey, uint256 _tokenId) public returns (address user) {
        user = vm.addr(_privateKey);
        pkey[user] = _privateKey;
        vm.deal(user, INITIAL_BALANCE);
        MockERC721(erc721).mint(user, _tokenId);
        return user;
    }

    /// =======================
    /// ===== VAULT PROXY =====
    /// =======================
    function setUpExecute(address _user) public returns (bytes memory data) {
        vm.prank(_user);
        IERC721(erc721).safeTransferFrom(_user, vault, 1);
        data = abi.encodeCall(
            transferTarget.ERC721TransferFrom,
            (address(erc721), vault, _user, 1)
        );
    }

    /// ==========================
    /// ===== VAULT REGISTRY =====
    /// ==========================
    function setUpCreateFor(address _user) public {
        setUpProof();
        InitInfo[] memory calls = new InitInfo[](1);
        calls[0] = InitInfo({
            target: address(supplyTarget),
            data: abi.encodeCall(ISupply.mint, (alice, TOTAL_SUPPLY)),
            proof: mintProof
        });
        vault = registry.createFor(merkleRoot, _user, calls);

        vm.label(vault, "VaultProxy");
    }

    /// ====================
    /// ===== Rae =====
    /// ====================
    function setUpPermit(
        address _user,
        bool _approved,
        uint256 _deadline
    ) public {
        approved = _approved;
        deadline = _deadline;
        vm.prank(_user);
        IERC721(erc721).safeTransferFrom(_user, vault, 1);
        (token, tokenId) = registry.vaultToToken(vault);
        nonce = Rae(token).nonces(_user);
        vm.label(vault, "VaultProxy");
    }

    function setUpVault(address _user) public {
        setUpProof();
        InitInfo[] memory calls = new InitInfo[](1);
        calls[0] = InitInfo({
            target: address(supplyTarget),
            data: abi.encodeCall(ISupply.mint, (alice, TOTAL_SUPPLY)),
            proof: mintProof
        });

        (vault, token) = registry.createCollectionFor(merkleRoot, _user, calls);
        (, tokenId) = registry.vaultToToken(address(vault));
    }

    /// ======================
    /// ===== BASE VAULT =====
    /// ======================
    function deployBaseVault(address _user) public virtual {
        setUpProof();
        InitInfo[] memory calls = new InitInfo[](1);
        calls[0] = InitInfo({
            target: address(supplyTarget),
            data: abi.encodeCall(ISupply.mint, (_user, TOTAL_SUPPLY)),
            proof: mintProof
        });

        vm.startPrank(_user);
        vault = baseVault.deployVault(modules, calls);
        IERC721(erc721).safeTransferFrom(_user, vault, 1);
        vm.stopPrank();
        vm.label(vault, "VaultProxy");
    }

    function setUpMulticall(address _user) public {
        MockERC20(erc20).mint(_user, 10);
        MockERC721(erc721).mint(_user, 2);
        MockERC721(erc721).mint(_user, 3);
        mintERC1155(_user, 2);

        setERC20Approval(erc20, _user, address(baseVault), true);
        setERC721Approval(erc721, _user, address(baseVault), true);
        setERC1155Approval(erc1155, _user, address(baseVault), true);
    }

    function initializeDepositERC20(uint256 _amount)
        public
        view
        returns (bytes memory depositERC721)
    {
        address[] memory tokens = new address[](1);
        tokens[0] = erc20;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amount;

        depositERC721 = abi.encodeCall(baseVault.batchDepositERC20, (vault, tokens, amounts));
    }

    function initializeDepositERC721(uint256 _count)
        public
        view
        returns (bytes memory depositERC721)
    {
        address[] memory nfts = new address[](_count);
        uint256[] memory tokenIds = new uint256[](_count);
        for (uint256 i; i < _count; i++) {
            nfts[i] = erc721;
            tokenIds[i] = i + 2;
        }

        depositERC721 = abi.encodeCall(baseVault.batchDepositERC721, (vault, nfts, tokenIds));
    }

    function initializeDepositERC1155(uint256 _count)
        public
        view
        returns (bytes memory depositERC1155)
    {
        address[] memory nfts = new address[](_count);
        uint256[] memory tokenIds = new uint256[](_count);
        uint256[] memory amounts = new uint256[](_count);
        bytes[] memory data = new bytes[](_count);
        for (uint256 i; i < _count; i++) {
            nfts[i] = erc1155;
            tokenIds[i] = i + 1;
            amounts[i] = 10;
            data[i] = "";
        }

        depositERC1155 = abi.encodeCall(
            baseVault.batchDepositERC1155,
            (vault, nfts, tokenIds, amounts, data)
        );
    }

    /// ===================
    /// ===== HELPERS =====
    /// ===================
    function setERC1155Approval(
        address _token,
        address _user,
        address _operator,
        bool _approval
    ) public {
        vm.prank(_user);
        IERC1155(_token).setApprovalForAll(_operator, _approval);
    }

    function setERC721Approval(
        address _token,
        address _user,
        address _operator,
        bool _approval
    ) public {
        vm.prank(_user);
        IERC721(_token).setApprovalForAll(_operator, _approval);
    }

    function setERC20Approval(
        address _token,
        address _user,
        address _operator,
        bool _approval
    ) public {
        uint256 amount = (_approval) ? type(uint256).max : 0;
        vm.prank(_user);
        IERC20(_token).approve(_operator, amount);
    }

    function mintERC1155(address _to, uint256 _count) public {
        for (uint256 i = 1; i <= _count; i++) {
            MockERC1155(erc1155).mint(_to, i, 10, "");
        }
    }

    function getRaeBalance(address _account) public view returns (uint256) {
        return IERC1155(token).balanceOf(_account, tokenId);
    }

    function getETHBalance(address _account) public view returns (uint256) {
        return _account.balance;
    }

    /// ======================
    /// ===== SIGNATURES =====
    /// ======================
    function computeDigest(bytes32 _domainSeparator, bytes32 _structHash)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode("\x19\x01", _domainSeparator, _structHash));
    }

    function computeDomainSeparator() public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    keccak256(bytes("Rae")),
                    keccak256(bytes("1")),
                    block.chainid,
                    token
                )
            );
    }

    function signPermit(
        address _owner,
        address _operator,
        bool _bool,
        uint256 _nonce,
        uint256 _deadline
    )
        public
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        )
    {
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, _owner, _operator, tokenId, _bool, _nonce++, _deadline)
        );

        (v, r, s) = vm.sign(pkey[_owner], computeDigest(computeDomainSeparator(), structHash));
    }

    function signPermitAll(
        address _owner,
        address _operator,
        bool _bool,
        uint256 _nonce,
        uint256 _deadline
    )
        public
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        )
    {
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_ALL_TYPEHASH, _owner, _operator, _bool, _nonce++, _deadline)
        );

        (v, r, s) = vm.sign(pkey[_owner], computeDigest(computeDomainSeparator(), structHash));
    }

    modifier prank(address _who) {
        vm.startPrank(_who);
        _;
        vm.stopPrank();
    }
}
