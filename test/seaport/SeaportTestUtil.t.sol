// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.13;

import "../TestUtil.sol";
import {OptimisticListingSeaport} from "../../src/seaport/modules/OptimisticListingSeaport.sol";
import {SeaportLister} from "../../src/seaport/targets/SeaportLister.sol";
import {IOptimisticListingSeaport, Listing} from "../../src/seaport/interfaces/IOptimisticListingSeaport.sol";
import {ISeaportLister} from "../../src/seaport/interfaces/ISeaportLister.sol";

import {ConsiderationItem, ItemType, OfferItem, Order, OrderParameters, OrderComponents, OrderType} from "seaport/lib/ConsiderationStructs.sol";
import {ConsiderationInterface as ISeaport} from "seaport/interfaces/ConsiderationInterface.sol";
import {ConduitControllerInterface as IController} from "seaport/interfaces/ConduitControllerInterface.sol";

contract SeaportTestUtil is TestUtil, NFTReceiver {
    // identifier for goerli fork
    uint256 goerliFork;

    // Fourth Address user as the buyer
    address public susan;
    // Optimistic Listing contracts
    OptimisticListingSeaport optimistic;
    SeaportLister lister;

    // Proofs
    bytes32[] public validateProof;
    bytes32[] public cancelProof;

    //Balances
    uint256 aliceEtherBalance;
    uint256 aliceTokenBalance;
    uint256 bobEtherBalance;
    uint256 bobTokenBalance;
    uint256 eveEtherBalance;
    uint256 eveTokenBalance;
    uint256 susanEtherBalance;
    uint256 susanTokenBalance;
    uint256 vaultEtherBalance;

    // Constants
    address constant SEAPORT = 0x00000000006c3852cbEf3e08E8dF289169EdE581;
    address constant ZONE = address(0);
    address constant CONTROLLER = 0x00000000F9490004C11Cef243f5400493c00Ad63;
    bytes32 constant CONDUIT_KEY =
        0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000;
    uint256 constant ETHER_BALANCE = 150000 ether;
    uint256 constant ERC20_SUPPLY = 100;
    uint256 constant ERC721_SUPPLY = 10;
    uint256 constant ERC1155_SUPPLY = 5;
    uint256 constant QUARTER_SUPPLY = TOTAL_SUPPLY / 4;
    uint256 constant PROPOSAL_PERIOD = 3 days;
    uint256 constant MODULE_SIZE = 1;

    function setUpFork() public virtual {
        goerliFork = vm.createFork("goerli");
    }

    function setUpContract() public virtual override {
        setUpFork();
        vm.selectFork(goerliFork);
        assertEq(vm.activeFork(), goerliFork);
        super.setUpContract();
        vm.makePersistent(CONTROLLER);

        vm.label(CONTROLLER, "ConduitController");
        // Seaport Conduit
        (address conduit, ) = IController(CONTROLLER).getConduit(CONDUIT_KEY);
        lister = new SeaportLister(conduit);
        optimistic = new OptimisticListingSeaport(
            address(registry),
            SEAPORT,
            ZONE,
            CONDUIT_KEY,
            address(supplyTarget),
            address(lister),
            payable(FEES),
            payable(address(0)),
            PROPOSAL_PERIOD,
            payable(address(weth))
        );

        vm.label(conduit, "Conduit");
        vm.label(ZONE, "Zone");
        vm.label(address(lister), "SeaportLister");
        vm.label(address(optimistic), "OptimisticListingSeaport");

        alice = address(111);
        bob = address(222);
        eve = address(333);
        susan = address(444);
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(eve, "Eve");
        vm.label(susan, "Susan");

        vm.deal(alice, ETHER_BALANCE);
        vm.deal(bob, ETHER_BALANCE);
        vm.deal(eve, ETHER_BALANCE);
        vm.deal(susan, ETHER_BALANCE);
    }

    function setUpProof() public virtual override {
        modules = new address[](MODULE_SIZE);
        modules[0] = address(optimistic);

        merkleTree = baseVault.generateMerkleTree(modules);
        merkleRoot = baseVault.getRoot(merkleTree);
        burnProof = baseVault.getProof(merkleTree, 0);
        validateProof = baseVault.getProof(merkleTree, 1);
        cancelProof = baseVault.getProof(merkleTree, 2);
    }

    function deployBaseVault(address _user) public virtual override prank(_user) {
        setUpProof();
        InitInfo[] memory calls = new InitInfo[](1);
        calls[0] = InitInfo({
            target: address(supplyTarget),
            data: abi.encodeCall(ISupply.mint, (_user, TOTAL_SUPPLY)),
            proof: mintProof
        });
        vault = baseVault.deployVault(modules, calls);
        (token, tokenId) = registry.vaultToToken(vault);
        // mint assets
        _mintERC20(vault, ERC20_SUPPLY);
        _mintERC721(vault, ERC721_SUPPLY);
        _mintERC1155(vault, ERC1155_SUPPLY);
        vm.label(vault, "VaultProxy");
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

    /// Mints ERC20 tokens to given account
    function _mintERC20(address _to, uint256 _amount) internal {
        MockERC20(erc20).mint(_to, _amount);
    }

    /// Mints ERC721 tokens to given account
    function _mintERC721(address _to, uint256 _amount) internal {
        for (uint256 i; i < _amount; ++i) {
            MockERC721(erc721).mint(_to, i);
        }
    }

    /// Mints ERC1155 tokens to given account
    function _mintERC1155(address _to, uint256 _amount) internal {
        for (uint256 i; i < _amount; ++i) {
            MockERC1155(erc1155).mint(_to, i, _amount, "");
        }
    }

    // Might want to replace this with a function that fulfills  the order
    function _transferItems(address _owner, address _to) internal prank(_owner) {
        MockERC20(erc20).transferFrom(_owner, _to, ERC20_SUPPLY);
        for (uint256 i = 0; i < ERC721_SUPPLY; ++i) {
            MockERC721(erc721).safeTransferFrom(_owner, _to, i);
        }
        for (uint256 i = 0; i < ERC1155_SUPPLY; ++i) {
            MockERC1155(erc721).safeTransferFrom(_owner, _to, i, ERC1155_SUPPLY, "");
        }
    }

    /// Sets approval for FERC-1155 Token contract
    function _setTokenApproval(
        address _owner,
        address _operator,
        address _token,
        bool _approval
    ) internal prank(_owner) {
        IERC1155(_token).setApprovalForAll(_operator, _approval);
    }

    // Transfers FERC-1155 token
    function _transferToken(
        address _from,
        address _to,
        address _token,
        uint256 _id,
        uint256 _amount
    ) internal prank(_from) {
        IERC1155(_token).safeTransferFrom(_from, _to, _id, _amount, "");
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

    function _assertItemOwnership(address _owner) internal {
        assertEq(MockERC20(erc20).balanceOf(_owner), ERC20_SUPPLY);
        assertEq(MockERC721(erc721).balanceOf(_owner), ERC721_SUPPLY);
        for (uint256 i = 0; i < ERC1155_SUPPLY; ++i) {
            assertEq(MockERC1155(erc1155).balanceOf(_owner, i), ERC1155_SUPPLY);
        }
    }

    /// Increases block time by duration
    function _increaseTime(uint256 _duration) internal {
        vm.warp(block.timestamp + _duration);
    }

    /// Decreases block time by duration
    function _decreaseTime(uint256 _duration) internal {
        vm.warp(block.timestamp - _duration);
    }
}
