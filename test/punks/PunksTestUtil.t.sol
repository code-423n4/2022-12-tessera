// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import {CryptoPunksMarket} from "../../src/punks/utils/CryptoPunksMarket.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockERC721} from "../../src/mocks/MockERC721.sol";
import {MockERC1155} from "../../src/mocks/MockERC1155.sol";
import {NFTReceiver} from "../../src/utils/NFTReceiver.sol";
import {NFTReceiver} from "../../src/utils/NFTReceiver.sol";
import {OptimisticListingPunks} from "../../src/punks/modules/OptimisticListingPunks.sol";
import {PunksMarketLister} from "../../src/punks/targets/PunksMarketLister.sol";
import {PunksProtoform} from "../../src/punks/protoforms/PunksProtoform.sol";
import {Supply} from "../../src/targets/Supply.sol";
import {Transfer} from "../../src/targets/Transfer.sol";
import {VaultRegistry} from "../../src/VaultRegistry.sol";
import {WETH} from "@rari-capital/solmate/src/tokens/WETH.sol";
import {WrappedPunk} from "../../src/punks/utils/WrappedPunk.sol";

import {IERC1155} from "../../src/interfaces/IERC1155.sol";
import {IRae} from "../../src/interfaces/IRae.sol";
import {IOptimisticListingPunks} from "../../src/punks/interfaces/IOptimisticListingPunks.sol";
import {IPunksMarketLister} from "../../src/punks/interfaces/IPunksMarketLister.sol";
import {ISupply} from "../../src/interfaces/ISupply.sol";
import {ITransfer} from "../../src/interfaces/ITransfer.sol";
import {IVault, InitInfo} from "../../src/interfaces/IVault.sol";

contract PunksTestUtil is Test, NFTReceiver {
    // Contracts
    CryptoPunksMarket punks;
    MockERC20 erc20;
    MockERC721 erc721;
    MockERC1155 erc1155;
    OptimisticListingPunks optimistic;
    PunksMarketLister marketplace;
    PunksProtoform protoform;
    Supply supply;
    Transfer transfer;
    VaultRegistry registry;
    WETH weth;
    WrappedPunk wrapper;

    // Constants
    uint256 constant ETHER_BALANCE = 10000 ether;
    uint256 constant ERC20_SUPPLY = 100;
    uint256 constant ERC721_SUPPLY = 10;
    uint256 constant ERC1155_SUPPLY = 5;
    uint256 constant TOTAL_SUPPLY = 1000;
    uint256 constant HALF_SUPPLY = TOTAL_SUPPLY / 2;
    uint256 constant QUARTER_SUPPLY = TOTAL_SUPPLY / 4;
    uint256 constant PROPOSAL_PERIOD = 3 days;
    uint256 constant MODULE_SIZE = 2;
    uint256 constant PROOF_SIZE = 4;

    // Storage
    address adapter;
    address proxy;
    address token;
    address vault;
    bytes32 merkleRoot;
    uint256 id;
    uint256 punkId;

    // Permissions
    bytes32[] merkleTree;
    address[] modules = new address[](MODULE_SIZE);
    bytes32[] mintProof = new bytes32[](PROOF_SIZE);
    bytes32[] burnProof = new bytes32[](PROOF_SIZE);
    bytes32[] unwrapProof = new bytes32[](PROOF_SIZE);
    bytes32[] transferPunkProof = new bytes32[](PROOF_SIZE);
    bytes32[] listProof = new bytes32[](PROOF_SIZE);
    bytes32[] delistProof = new bytes32[](PROOF_SIZE);
    bytes32[] withdrawProof = new bytes32[](PROOF_SIZE);
    bytes32[] ethTransferProof = new bytes32[](PROOF_SIZE);
    bytes32[] erc20TransferProof = new bytes32[](PROOF_SIZE - 1);
    bytes32[] erc721TransferProof = new bytes32[](PROOF_SIZE - 1);
    bytes32[] erc1155TransferProof = new bytes32[](PROOF_SIZE - 2);

    // Users
    address alice = address(111);
    address bob = address(222);
    address eve = address(333);
    address susan = address(444);

    // Balances
    uint256 aliceEtherBalance;
    uint256 aliceTokenBalance;
    uint256 bobEtherBalance;
    uint256 bobTokenBalance;
    uint256 eveEtherBalance;
    uint256 eveTokenBalance;
    uint256 susanEtherBalance;
    uint256 susanTokenBalance;
    uint256 vaultEtherBalance;

    // Deploys all contracts
    function _setUpContract() internal {
        weth = new WETH();
        registry = new VaultRegistry();
        supply = new Supply(address(registry));
        transfer = new Transfer();
        punks = new CryptoPunksMarket();
        wrapper = new WrappedPunk(address(punks));
        marketplace = new PunksMarketLister(address(punks), address(wrapper));
        optimistic = new OptimisticListingPunks(
            address(registry),
            address(supply),
            address(transfer),
            address(marketplace),
            address(punks),
            PROPOSAL_PERIOD,
            payable(weth)
        );
        protoform = new PunksProtoform(
            address(registry),
            address(wrapper),
            address(optimistic),
            address(supply)
        );
        erc20 = new MockERC20();
        erc721 = new MockERC721();
        erc1155 = new MockERC1155();

        vm.label(address(punks), "CryptoPunksMarket");
        vm.label(address(marketplace), "PunksMarketLister");
        vm.label(address(optimistic), "OptimisticListingPunks");
        vm.label(address(protoform), "PunksProtoform");
        vm.label(address(registry), "VaultRegistry");
        vm.label(address(supply), "Supply");
        vm.label(address(transfer), "Transfer");
        vm.label(address(wrapper), "WrappedPunk");

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(eve, "Eve");
        vm.label(susan, "Susan");

        vm.deal(alice, ETHER_BALANCE);
        vm.deal(bob, ETHER_BALANCE);
        vm.deal(eve, ETHER_BALANCE);
        vm.deal(susan, ETHER_BALANCE);
    }

    /// Generates merkle tree and proofs
    function _setUpProof() internal virtual {
        modules[0] = address(protoform);
        modules[1] = address(optimistic);
        merkleTree = protoform.generateMerkleTree(modules);
        merkleRoot = protoform.getRoot(merkleTree);
        // Minter permissions
        mintProof = protoform.getProof(merkleTree, 0);
        // OptimisticListing permissions
        burnProof = protoform.getProof(merkleTree, 1);
        unwrapProof = protoform.getProof(merkleTree, 2);
        transferPunkProof = protoform.getProof(merkleTree, 3);
        listProof = protoform.getProof(merkleTree, 4);
        delistProof = protoform.getProof(merkleTree, 5);
        withdrawProof = protoform.getProof(merkleTree, 6);
        ethTransferProof = protoform.getProof(merkleTree, 7);
        erc20TransferProof = protoform.getProof(merkleTree, 8);
        erc721TransferProof = protoform.getProof(merkleTree, 9);
        erc1155TransferProof = protoform.getProof(merkleTree, 10);
    }

    /// Deploys new protoform vault
    function _deployVault(
        address _owner,
        uint256 _punkId,
        bytes32[] storage _mintProof,
        bytes32[] storage _unwrapProof
    ) internal prank(_owner) {
        vault = protoform.deployVault(_punkId, TOTAL_SUPPLY, modules, _mintProof, _unwrapProof);

        (token, id) = registry.vaultToToken(vault);
        adapter = optimistic.adapters(vault);

        vm.label(adapter, "Adapter");
        vm.label(vault, "Vault");
        vm.label(token, "Token");
    }

    /// Mints ERC20 tokens to given account
    function _mintERC20(address _to, uint256 _amount) internal {
        erc20.mint(_to, _amount);
    }

    /// Mints ERC721 tokens to given account
    function _mintERC721(address _to, uint256 _amount) internal {
        for (uint256 i; i < _amount; ++i) {
            erc721.mint(_to, i);
        }
    }

    /// Mints ERC1155 tokens to given account
    function _mintERC1155(address _to, uint256 _amount) internal {
        for (uint256 i; i < _amount; ++i) {
            erc1155.mint(_to, i, _amount, "");
        }
    }

    /// Sets owner of punk
    function _setOwner(
        address _deployer,
        address _to,
        uint256 _punkId
    ) internal prank(_deployer) {
        punks.setInitialOwner(_to, _punkId);
    }

    /// Finalizes assignment of all owners
    function _setAssigned(address _deployer) internal prank(_deployer) {
        punks.allInitialOwnersAssigned();
    }

    /// Registers new proxy
    function _registerProxy(address _owner) internal prank(_owner) {
        wrapper.registerProxy();
        proxy = wrapper.proxyInfo(_owner);

        vm.label(proxy, "Proxy");
    }

    /// Transfers punk
    function _transferPunk(
        address _owner,
        address _to,
        uint256 _punkId
    ) internal prank(_owner) {
        punks.transferPunk(_to, _punkId);
    }

    /// Wraps punk
    function _wrapPunk(address _owner, uint256 _punkId) internal prank(_owner) {
        wrapper.mint(_punkId);
    }

    /// Unwraps punk
    function _unwrapPunk(address _owner, uint256 _punkId) internal prank(_owner) {
        wrapper.burn(_punkId);
    }

    /// Sets approval for WrappedPunk contract
    function _setWrapperApproval(
        address _owner,
        address _operator,
        bool _approval
    ) internal prank(_owner) {
        wrapper.setApprovalForAll(_operator, _approval);
    }

    /// Sets approval for Rae-1155 Token contract
    function _setTokenApproval(
        address _owner,
        address _operator,
        address _token,
        bool _approval
    ) internal prank(_owner) {
        IERC1155(_token).setApprovalForAll(_operator, _approval);
    }

    // Transfers Rae-1155 token
    function _transferToken(
        address _from,
        address _to,
        address _token,
        uint256 _id,
        uint256 _amount
    ) internal prank(_from) {
        IERC1155(_token).safeTransferFrom(_from, _to, _id, _amount, "");
    }

    /// Initializes ether balances for all users
    function _initializeEtherBalance() internal {
        aliceEtherBalance = alice.balance;
        bobEtherBalance = bob.balance;
        eveEtherBalance = eve.balance;
        susanEtherBalance = susan.balance;

        vm.deal(vault, ETHER_BALANCE);
        vaultEtherBalance = vault.balance;
    }

    /// Initializes token balances for all users
    function _initializeTokenBalance(address _token, uint256 _id) internal {
        aliceTokenBalance = IERC1155(_token).balanceOf(alice, _id);
        bobTokenBalance = IERC1155(_token).balanceOf(bob, _id);
        eveTokenBalance = IERC1155(_token).balanceOf(eve, _id);
        susanTokenBalance = IERC1155(_token).balanceOf(susan, _id);
    }

    // Checks owner of punk
    function _assertPunkOwner(address _owner, uint256 _punkId) internal {
        assertEq(punks.punkIndexToAddress(_punkId), _owner);
    }

    /// Checks token balance of owner
    function _assertTokenBalance(
        address _owner,
        address _token,
        uint256 _id,
        uint256 _amount
    ) internal {
        assertEq(IERC1155(_token).balanceOf(_owner, _id), _amount);
    }

    /// Increases block time by duration
    function _increaseTime(uint256 _duration) internal {
        vm.warp(block.timestamp + _duration);
    }

    /// Decreases block time by duration
    function _decreaseTime(uint256 _duration) internal {
        vm.warp(block.timestamp - _duration);
    }

    /// Prank modifier
    modifier prank(address _who) {
        vm.startPrank(_who);
        _;
        vm.stopPrank();
    }

    /// Fallback for receiving ether
    receive() external payable {}

    /// Fallback for unidentified function OR no calldata
    fallback() external payable {}
}
