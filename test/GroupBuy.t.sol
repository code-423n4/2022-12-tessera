// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.13;

import "./TestUtil.sol";
import {CryptoPunksMarket} from "./punks/PunksTestUtil.t.sol";
import {GroupBuy} from "../src/modules/GroupBuy.sol";
import {MerkleBase} from "../src/utils/MerkleBase.sol";
import {OptimisticListingPunks} from "../src/punks/modules/OptimisticListingPunks.sol";
import {PunksMarketBuyer} from "../src/punks/protoforms/PunksMarketBuyer.sol";
import {PunksMarketLister} from "../src/punks/targets/PunksMarketLister.sol";
import {WrappedPunk} from "../src/punks/utils/WrappedPunk.sol";

import {IGroupBuy} from "../src/interfaces/IGroupBuy.sol";
import {IMarketBuyer} from "../src/interfaces/IMarketBuyer.sol";

// USER ROLES
// Deployer: GroupBuyTest => address(this)
// Creator: Alice => address(111)
// Contributor: Bob => address(222)
// Contributor: Eve => address(333)
contract GroupBuyTest is TestUtil, MerkleBase {
    // Contracts
    CryptoPunksMarket punks;
    GroupBuy groupBuy;
    OptimisticListingPunks listing;
    PunksMarketBuyer punksBuyer;
    PunksMarketLister marketplace;
    WrappedPunk wrapper;

    // Pool
    address nftContract;
    uint48 totalSupply;
    uint40 terminationPeriod;
    bool success;
    bytes32 nftMerkleRoot;

    // Bid
    uint256 bidId;
    address owner;
    uint256 price;
    uint256 quantity;

    // Queue
    uint256 nextBidId;
    uint256 numBids;

    // Storage
    uint40 duration;
    uint256 initialPrice;
    uint256 ethContribution;
    uint256 currentId;
    uint256 filledQuantity;
    uint256 minReservePrice;
    uint256 totalContribution;
    uint256 userContribution;
    bytes purchaseOrder;

    // Contributions
    uint256 alicePrice;
    uint256 bobPrice;
    uint256 evePrice;
    uint256 aliceQuantity;
    uint256 bobQuantity;
    uint256 eveQuantity;
    uint256 aliceContribution;
    uint256 bobContribution;
    uint256 eveContribution;
    uint256[] aliceBidIds;
    uint256[] bobBidIds;
    uint256[] eveBidIds;

    // Merkle Tree
    uint256[] tokenIds = [0, 1, 2];
    bytes32[] punksTree = new bytes32[](3);
    bytes32[] purchaseProof = new bytes32[](2);

    // Punks
    uint256 punkId = 1;
    bool isForSale;
    address seller;
    uint256 minValue;

    // Punks Protoform
    address[] punksModules = new address[](2);
    bytes32[] punksMintProof = new bytes32[](4);
    bytes32[] punksUnwrapProof = new bytes32[](4);

    // Constants
    uint256 constant MIN_PRICE = 0.01 ether;
    uint256 constant MAX_PRICE = 1 ether;
    uint256 constant MIN_SUPPLY = 1;
    uint256 constant MAX_SUPPLY = 10000;
    uint256 constant MIN_TIME = 1 days;
    uint256 constant MAX_TIME = 365 days;

    // Errors
    bytes4 INSUFFICIENT_BALANCE_ERROR = IGroupBuy.InsufficientBalance.selector;
    bytes4 INSUFFICIENT_TOKEND_IDS_ERROR = IGroupBuy.InsufficientTokenIds.selector;
    bytes4 INVALID_CONTRACT_ERROR = IGroupBuy.InvalidContract.selector;
    bytes4 INVALID_CONTRIBUTION_ERROR = IGroupBuy.InvalidContribution.selector;
    bytes4 INVALID_PAYMENT_ERROR = IGroupBuy.InvalidPayment.selector;
    bytes4 INVALID_POOL_ERROR = IGroupBuy.InvalidPool.selector;
    bytes4 INVALID_PROOF_ERROR = IGroupBuy.InvalidProof.selector;
    bytes4 INVALID_PURCHASE_ERROR = IGroupBuy.InvalidPurchase.selector;
    bytes4 INVALID_STATE_ERROR = IGroupBuy.InvalidState.selector;
    bytes4 NOT_OWNER_ERROR = IGroupBuy.NotOwner.selector;
    bytes4 UNSUCCESSFUL_PURCHASE_ERROR = IGroupBuy.UnsuccessfulPurchase.selector;

    /// =================
    /// ===== SETUP =====
    /// =================
    function setUp() public {
        setUpContract();
        punks = new CryptoPunksMarket();
        wrapper = new WrappedPunk(address(punks));
        groupBuy = new GroupBuy(address(supplyTarget));
        marketplace = new PunksMarketLister(address(punks), address(wrapper));
        listing = new OptimisticListingPunks(
            address(registry),
            address(supplyTarget),
            address(transferTarget),
            address(marketplace),
            address(punks),
            7 days,
            payable(weth)
        );
        punksBuyer = new PunksMarketBuyer(address(registry), address(wrapper), address(listing));
        punks.setInitialOwner(address(this), punkId);
        punks.allInitialOwnersAssigned();
        punks.offerPunkForSale(punkId, 100 ether);
        _setPunkOffer(punkId);

        punksModules[0] = address(groupBuy);
        punksModules[1] = address(listing);
        merkleTree = punksBuyer.generateMerkleTree(punksModules);
        merkleRoot = punksBuyer.getRoot(merkleTree);
        punksMintProof = punksBuyer.getProof(merkleTree, 0);
        punksUnwrapProof = punksBuyer.getProof(merkleTree, 2);

        punksTree[0] = keccak256(abi.encode(tokenIds[0]));
        punksTree[1] = keccak256(abi.encode(tokenIds[1]));
        punksTree[2] = keccak256(abi.encode(tokenIds[2]));
        purchaseProof = getProof(punksTree, punkId);

        alice = setUpUser(111, 0);
        bob = setUpUser(222, 1);
        eve = setUpUser(333, 2);

        vm.label(address(punks), "CryptoPunksMarket");
        vm.label(address(groupBuy), "GroupBuy");
        vm.label(address(this), "GroupBuyTest");
        vm.label(address(punksBuyer), "PunksMarketBuyer");

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(eve, "Eve");
    }

    /// =======================
    /// ===== CREATE POOL =====
    /// =======================
    function testCreatePoolSuccess(
        uint256 _totalSupply,
        uint256 _duration,
        uint256 _quantity,
        uint256 _raePrice
    ) public {
        // setup
        _totalSupply = _boundSupply(_totalSupply);
        _duration = _boundTermination(_duration);
        _quantity = _boundQuantity(_quantity, _totalSupply);
        _raePrice = _boundPrice(_raePrice);
        ethContribution = _quantity * _raePrice;
        initialPrice = MIN_PRICE * _totalSupply;
        // execute
        _createPool(
            alice,
            address(punks),
            tokenIds,
            initialPrice,
            uint48(_totalSupply),
            uint40(_duration),
            _quantity,
            _raePrice,
            ethContribution
        );
        // expect
        assertEq(nftContract, address(punks));
        assertEq(terminationPeriod, uint40(block.timestamp) + uint40(_duration));
        assertEq(success, false);
        assertEq(nftMerkleRoot, _generateRoot(tokenIds));
        assertEq(userContribution, ethContribution);
        assertEq(totalContribution, ethContribution);
        assertEq(alice.balance, INITIAL_BALANCE - ethContribution);
        assertEq(address(groupBuy).balance, ethContribution);
    }

    function testCreatePoolSingleTokenID(
        uint256 _initialPrice,
        uint256 _totalSupply,
        uint256 _duration,
        uint256 _quantity,
        uint256 _raePrice
    ) public {
        // setUpProof
        tokenIds = new uint256[](1);
        _totalSupply = _boundSupply(_totalSupply);
        _duration = _boundTermination(_duration);
        _quantity = _boundQuantity(_quantity, _totalSupply);
        _raePrice = _boundPrice(_raePrice);
        ethContribution = _quantity * _raePrice;
        initialPrice = MIN_PRICE * _totalSupply;
        // execute
        _createPool(
            alice,
            address(punks),
            tokenIds,
            initialPrice,
            uint48(_totalSupply),
            uint40(_duration),
            _quantity,
            _raePrice,
            ethContribution
        );
        // expect
        assertEq(nftContract, address(punks));
        assertEq(totalSupply, uint48(_totalSupply));
        assertEq(terminationPeriod, uint40(block.timestamp) + uint40(_duration));
        assertEq(success, false);
        assertEq(nftMerkleRoot, bytes32(tokenIds[0]));
        assertEq(userContribution, ethContribution);
        assertEq(totalContribution, ethContribution);
        assertEq(alice.balance, INITIAL_BALANCE - ethContribution);
        assertEq(address(groupBuy).balance, ethContribution);
    }

    function testCreatePoolRevertInsufficientTokenIds(
        uint256 _initialPrice,
        uint256 _totalSupply,
        uint256 _duration,
        uint256 _quantity,
        uint256 _raePrice
    ) public {
        // setup
        tokenIds = new uint256[](0);
        _totalSupply = _boundSupply(_totalSupply);
        _duration = _boundTermination(_duration);
        _quantity = _boundQuantity(_quantity, _totalSupply);
        _raePrice = _boundPrice(_raePrice);
        ethContribution = _quantity * _raePrice;
        initialPrice = MIN_PRICE * _totalSupply;
        // expect
        vm.expectRevert(INSUFFICIENT_TOKEND_IDS_ERROR);
        // execute
        _createPool(
            alice,
            address(punks),
            tokenIds,
            initialPrice,
            uint48(_totalSupply),
            uint40(_duration),
            _quantity,
            _raePrice,
            ethContribution
        );
    }

    /// ======================
    /// ===== CONTRIBUTE =====
    /// ======================
    function testContributeSuccess() public {
        // setup
        totalSupply = 1000;
        duration = 30 days;
        aliceQuantity = 600;
        alicePrice = 1 ether;
        bobQuantity = 500;
        bobPrice = 2 ether;
        eveQuantity = 400;
        evePrice = 3 ether;
        initialPrice = MIN_PRICE * totalSupply;

        // execute
        _createPool(
            alice,
            address(punks),
            tokenIds,
            initialPrice,
            totalSupply,
            duration,
            aliceQuantity,
            alicePrice,
            aliceQuantity * alicePrice
        );
        /* groupBuy.printQueue(currentId); */
        _setBidIds(currentId);
        _setContributionValues(currentId);
        // expect
        assertEq(filledQuantity, aliceQuantity);
        assertEq(minReservePrice, alicePrice);
        assertEq(totalContribution, aliceQuantity * alicePrice);
        assertEq(aliceContribution, aliceQuantity * alicePrice);
        _setBidValues(currentId, aliceBidIds[0]);
        assertEq(owner, alice);
        assertEq(quantity, aliceQuantity);
        assertEq(price, alicePrice);

        // execute
        _contribute(bob, currentId, bobQuantity, bobPrice, bobQuantity * bobPrice);
        /* groupBuy.printQueue(currentId); */
        _setBidIds(currentId);
        _setContributionValues(currentId);
        // expect
        assertEq(filledQuantity, totalSupply);
        assertEq(minReservePrice, alicePrice);
        assertEq(
            totalContribution,
            (aliceQuantity * alicePrice) +
                (bobQuantity * bobPrice) -
                ((aliceQuantity - bobQuantity) * alicePrice)
        );
        assertEq(aliceContribution, aliceQuantity * alicePrice - groupBuy.pendingBalances(alice));
        assertEq(bobContribution, bobQuantity * bobPrice);
        _setBidValues(currentId, aliceBidIds[0]);
        assertEq(owner, alice);
        assertEq(quantity, totalSupply - bobQuantity);
        assertEq(price, alicePrice);
        _setBidValues(currentId, bobBidIds[0]);
        assertEq(owner, bob);
        assertEq(quantity, bobQuantity - (aliceQuantity - bobQuantity));
        assertEq(price, bobPrice);
        _setBidValues(currentId, bobBidIds[1]);
        assertEq(owner, bob);
        assertEq(quantity, aliceQuantity - bobQuantity);
        assertEq(price, bobPrice);

        // execute
        _contribute(eve, currentId, eveQuantity, evePrice, eveQuantity * evePrice);
        /* groupBuy.printQueue(currentId); */
        _setBidIds(currentId);
        _setContributionValues(currentId);
        // expect
        assertEq(filledQuantity, totalSupply);
        assertEq(minReservePrice, alicePrice);
        assertEq(
            totalContribution,
            (aliceQuantity * alicePrice) +
                (bobQuantity * bobPrice) +
                (eveQuantity * evePrice) -
                ((aliceQuantity - bobQuantity) * alicePrice) -
                (eveQuantity * alicePrice)
        );
        assertEq(aliceContribution, aliceQuantity * alicePrice - groupBuy.pendingBalances(alice));
        assertEq(bobContribution, bobQuantity * bobPrice);
        assertEq(eveContribution, eveQuantity * evePrice);
        _setBidValues(currentId, aliceBidIds[0]);
        assertEq(owner, alice);
        assertEq(quantity, totalSupply - bobQuantity - eveQuantity);
        assertEq(price, alicePrice);
        _setBidValues(currentId, bobBidIds[0]);
        assertEq(owner, bob);
        assertEq(quantity, bobQuantity - (aliceQuantity - bobQuantity));
        assertEq(price, bobPrice);
        _setBidValues(currentId, bobBidIds[1]);
        assertEq(owner, bob);
        assertEq(quantity, aliceQuantity - bobQuantity);
        assertEq(price, bobPrice);
        _setBidValues(currentId, eveBidIds[0]);
        assertEq(owner, eve);
        assertEq(quantity, eveQuantity);
        assertEq(price, evePrice);
    }

    function testContributeRevertInvalidPool(
        uint256 _initialPrice,
        uint256 _totalSupply,
        uint256 _duration,
        uint256 _quantity,
        uint256 _raePrice
    ) public {
        // setup
        testCreatePoolSuccess(_totalSupply, _duration, _quantity, _raePrice);
        _quantity = _boundQuantity(_quantity, totalSupply);
        _raePrice = _boundPrice(_raePrice);
        ethContribution = _quantity * _raePrice;
        currentId = 0;
        // expect
        vm.expectRevert(INVALID_POOL_ERROR);
        // execute
        _contribute(bob, currentId, _quantity, _raePrice, ethContribution);
    }

    function testContributeRevertInvalidStatePurchaseSuccess() public {
        // setup
        testPurchaseSuccess();
        ethContribution = bobQuantity * bobPrice;
        // expect
        vm.expectRevert(INVALID_STATE_ERROR);
        // execute
        _contribute(bob, currentId, bobQuantity, bobPrice, ethContribution);
    }

    function testContributeRevertInvalidStateTerminationPeriod(
        uint256 _initialPrice,
        uint256 _totalSupply,
        uint256 _duration,
        uint256 _quantity,
        uint256 _raePrice
    ) public {
        // setup
        testCreatePoolSuccess(_totalSupply, _duration, _quantity, _raePrice);
        _duration = _boundTermination(_duration);
        _quantity = _boundQuantity(_quantity, totalSupply);
        _raePrice = _boundPrice(_raePrice);
        ethContribution = _quantity * _raePrice;
        _increaseTime(_duration + 1);
        // expect
        vm.expectRevert(INVALID_STATE_ERROR);
        // execute
        _contribute(bob, currentId, _quantity, _raePrice, ethContribution);
    }

    function testContributeRevertInvalidContributionMinBidPrice(
        uint256 _initialPrice,
        uint256 _totalSupply,
        uint256 _duration,
        uint256 _quantity,
        uint256 _raePrice
    ) public {
        // setup
        testCreatePoolSuccess(_totalSupply, _duration, _quantity, _raePrice);
        _quantity = _boundQuantity(_quantity, totalSupply);
        _raePrice = MIN_PRICE - 1;
        ethContribution = _quantity * _raePrice;
        // expect
        vm.expectRevert(INVALID_CONTRIBUTION_ERROR);
        // execute
        _contribute(bob, currentId, _quantity, _raePrice, ethContribution);
    }

    function testContributeRevertInvalidContributionZeroQuantity(
        uint256 _initialPrice,
        uint256 _totalSupply,
        uint256 _duration,
        uint256 _quantity,
        uint256 _raePrice
    ) public {
        // setup
        testCreatePoolSuccess(_totalSupply, _duration, _quantity, _raePrice);
        _quantity = 0;
        _raePrice = _boundPrice(_raePrice);
        ethContribution = _quantity * _raePrice;
        // expect
        vm.expectRevert(INVALID_CONTRIBUTION_ERROR);
        // execute
        _contribute(bob, currentId, _quantity, _raePrice, ethContribution);
    }

    function testContributeRevertInvalidPayment(
        uint256 _initialPrice,
        uint256 _totalSupply,
        uint256 _duration,
        uint256 _quantity,
        uint256 _raePrice
    ) public {
        // setup
        testCreatePoolSuccess(_totalSupply, _duration, _quantity, _raePrice);
        _quantity = _boundQuantity(_quantity, totalSupply);
        _raePrice = _boundPrice(_raePrice);
        ethContribution = _quantity * _raePrice + 1;
        // expect
        vm.expectRevert(INVALID_PAYMENT_ERROR);
        // execute
        _contribute(bob, currentId, _quantity, _raePrice, ethContribution);
    }

    /// ====================
    /// ===== PURCHASE =====
    /// ====================
    function testPurchaseSuccess() public {
        // setup
        testContributeSuccess();
        uint256 prevTotalContribution = totalContribution;
        uint256 nftPrice = minValue;
        // execute
        _purchase(
            address(this),
            currentId,
            address(punksBuyer),
            address(punks),
            punkId,
            nftPrice,
            purchaseOrder,
            purchaseProof
        );
        // expect
        assertEq(isForSale, false);
        assertEq(seller, address(punksBuyer));
        assertEq(minValue, 0);
        assertEq(success, true);
        assertEq(punks.punkIndexToAddress(punkId), vault);
        assertEq(totalContribution, prevTotalContribution - nftPrice);
        assertEq(filledQuantity, totalSupply);
    }

    function testPurchaseSuccessUnfilledSupply() public {
        // setup
        totalSupply = 1000;
        duration = 30 days;
        aliceQuantity = 300;
        alicePrice = 1 ether;
        bobQuantity = 200;
        bobPrice = 2 ether;
        eveQuantity = 100;
        evePrice = 3 ether;
        initialPrice = MIN_PRICE * totalSupply;
        _createPool(
            alice,
            address(punks),
            tokenIds,
            initialPrice,
            totalSupply,
            duration,
            aliceQuantity,
            alicePrice,
            aliceQuantity * alicePrice
        );
        _contribute(bob, currentId, bobQuantity, bobPrice, bobQuantity * bobPrice);
        _contribute(eve, currentId, eveQuantity, evePrice, eveQuantity * evePrice);
        uint256 prevTotalContribution = totalContribution;
        uint256 nftPrice = minValue;
        // execute
        _purchase(
            address(this),
            currentId,
            address(punksBuyer),
            address(punks),
            punkId,
            nftPrice,
            purchaseOrder,
            purchaseProof
        );
        // expect
        assertEq(isForSale, false);
        assertEq(seller, address(punksBuyer));
        assertEq(minValue, 0);
        assertEq(success, true);
        assertEq(punks.punkIndexToAddress(punkId), vault);
        assertEq(totalContribution, prevTotalContribution - nftPrice);
        assertEq(filledQuantity, aliceQuantity + bobQuantity + eveQuantity);
    }

    function testPurchaseRevertInvalidPool() public {
        // setup
        testContributeSuccess();
        currentId += 1;
        // expect
        vm.expectRevert(INVALID_POOL_ERROR);
        // execute
        _purchase(
            address(this),
            currentId,
            address(punksBuyer),
            address(punks),
            punkId,
            minValue,
            purchaseOrder,
            purchaseProof
        );
    }

    function testPurchaseRevertInvalidContract() public {
        // setup
        testContributeSuccess();
        // expect
        vm.expectRevert(INVALID_CONTRACT_ERROR);
        // execute
        _purchase(
            address(this),
            currentId,
            address(punksBuyer),
            address(wrapper),
            punkId,
            minValue,
            purchaseOrder,
            purchaseProof
        );
    }

    function testPurchaseRevertInvalidStatePurchaseSuccess() public {
        // setup
        testPurchaseSuccess();
        // expect
        vm.expectRevert(INVALID_STATE_ERROR);
        // execute
        _purchase(
            address(this),
            currentId,
            address(punksBuyer),
            address(punks),
            punkId,
            minValue,
            purchaseOrder,
            purchaseProof
        );
    }

    function testPurchaseRevertInvalidStateTerminationPeriod() public {
        // setup
        testContributeSuccess();
        _increaseTime(terminationPeriod + 1);
        // expect
        vm.expectRevert(INVALID_STATE_ERROR);
        // execute
        _purchase(
            address(this),
            currentId,
            address(punksBuyer),
            address(punks),
            punkId,
            minValue,
            purchaseOrder,
            purchaseProof
        );
    }

    function testPurchaseRevertInvalidPurchase() public {
        // setup
        testContributeSuccess();
        punks.offerPunkForSale(punkId, totalContribution + 1);
        _setPunkOffer(punkId);
        // expect
        vm.expectRevert(INVALID_PURCHASE_ERROR);
        // execute
        _purchase(
            address(this),
            currentId,
            address(punksBuyer),
            address(punks),
            punkId,
            minValue,
            purchaseOrder,
            purchaseProof
        );
    }

    function testPurchaseRevertInvalidProof() public {
        // setup
        testContributeSuccess();
        // expect
        vm.expectRevert(INVALID_PROOF_ERROR);
        // execute
        _purchase(
            address(this),
            currentId,
            address(punksBuyer),
            address(punks),
            punkId,
            minValue,
            purchaseOrder,
            mintProof
        );
    }

    function xtestPurchaseRevertUnsuccessfullPurchase() public {
        // setup
        testContributeSuccess();
        address maliciousContract;
        // expect
        vm.expectRevert(UNSUCCESSFUL_PURCHASE_ERROR);
        // execute
        _purchase(
            address(this),
            currentId,
            maliciousContract,
            address(punks),
            punkId,
            minValue,
            purchaseOrder,
            purchaseProof
        );
    }

    /// =================
    /// ===== CLAIM =====
    /// =================
    function testClaimSuccess() public {
        // setup
        testPurchaseSuccess();

        // execute
        _claim(alice, currentId, punksMintProof);
        // expect
        assertEq(
            alice.balance,
            INITIAL_BALANCE - (IERC1155(token).balanceOf(alice, tokenId) * minReservePrice)
        );
        assertEq(
            IERC1155(token).balanceOf(alice, tokenId),
            totalSupply - bobQuantity - eveQuantity
        );
        assertEq(groupBuy.userContributions(currentId, alice), 0);

        // execute
        _claim(bob, currentId, punksMintProof);
        // expect
        assertEq(bob.balance, INITIAL_BALANCE - (bobQuantity * minReservePrice));
        assertEq(IERC1155(token).balanceOf(bob, tokenId), bobQuantity);
        assertEq(groupBuy.userContributions(currentId, bob), 0);

        // execute
        _claim(eve, currentId, punksMintProof);
        // expect
        assertEq(eve.balance, INITIAL_BALANCE - (eveQuantity * minReservePrice));
        assertEq(IERC1155(token).balanceOf(eve, tokenId), eveQuantity);
        assertEq(groupBuy.userContributions(currentId, eve), 0);
    }

    function testClaimTerminationPerido() public {
        // setup
        testContributeSuccess();
        _increaseTime(terminationPeriod + 1);

        // execute
        _claim(alice, currentId, punksMintProof);
        // expect
        assertEq(alice.balance, INITIAL_BALANCE);
        assertEq(groupBuy.userContributions(currentId, alice), 0);

        // execute
        _claim(bob, currentId, punksMintProof);
        // expect
        assertEq(bob.balance, INITIAL_BALANCE);
        assertEq(groupBuy.userContributions(currentId, bob), 0);

        // execute
        _claim(eve, currentId, punksMintProof);
        // expect
        assertEq(eve.balance, INITIAL_BALANCE);
        assertEq(groupBuy.userContributions(currentId, eve), 0);
    }

    function testClaimRevertInvalidPool() public {
        // setup
        testPurchaseSuccess();
        currentId += 1;
        // expect
        vm.expectRevert(INVALID_POOL_ERROR);
        // execute
        _claim(alice, currentId, punksMintProof);
    }

    function testClaimRevertInvalidState() public {
        // setup
        testContributeSuccess();
        // expect
        vm.expectRevert(INVALID_STATE_ERROR);
        // execute
        _claim(alice, currentId, punksMintProof);
    }

    function testClaimRevertInsufficientBalance() public {
        // setup
        testPurchaseSuccess();
        _claim(alice, currentId, punksMintProof);
        // expect
        vm.expectRevert(INSUFFICIENT_BALANCE_ERROR);
        // execute
        _claim(alice, currentId, punksMintProof);
    }

    /// ============================
    /// ===== WITHDRAW BALANCE =====
    /// ============================
    function testWithdrawBalanceSuccess() public {
        // setup
        testPurchaseSuccess();
        // execute
        _withdrawBalance(alice);
        // expect
        assertEq(alice.balance, INITIAL_BALANCE - userContribution);
    }

    function testWithdrawBalanceRevertInsufficientBalance() public {
        // setup
        testClaimSuccess();
        // expect
        vm.expectRevert(INSUFFICIENT_BALANCE_ERROR);
        // execute
        _withdrawBalance(alice);
    }

    /// ===================
    /// ===== HELPERS =====
    /// ===================

    /// Creates new pool
    function _createPool(
        address _who,
        address _nftContract,
        uint256[] storage _tokenIds,
        uint256 _initialPrice,
        uint48 _totalSupply,
        uint40 _duration,
        uint256 _quantity,
        uint256 _raePrice,
        uint256 _contribution
    ) internal prank(_who) {
        groupBuy.createPool{value: _contribution}(
            _nftContract,
            _tokenIds,
            _initialPrice,
            _totalSupply,
            _duration,
            _quantity,
            _raePrice
        );
        _setCurrentId();
        _setGlobalState(currentId, _who);
    }

    /// Contributes into existing pool
    function _contribute(
        address _who,
        uint256 _poolId,
        uint256 _quantity,
        uint256 _price,
        uint256 _contribution
    ) internal prank(_who) {
        groupBuy.contribute{value: _contribution}(_poolId, _quantity, _price);
        _setGlobalState(_poolId, _who);
    }

    /// Purchases NFT with pool contributions
    function _purchase(
        address _who,
        uint256 _poolId,
        address _market,
        address _nftContract,
        uint256 _tokenId,
        uint256 _price,
        bytes memory _purchaseOrder,
        bytes32[] memory _purchaseProof
    ) internal prank(_who) {
        groupBuy.purchase(
            _poolId,
            _market,
            _nftContract,
            _tokenId,
            _price,
            _purchaseOrder,
            _purchaseProof
        );

        _setGlobalState(_poolId, _who);
        _setPunkOffer(_tokenId);

        vault = groupBuy.poolToVault(currentId);
        (token, tokenId) = registry.vaultToToken(vault);

        vm.label(vault, "Vault");
        vm.label(token, "Rae");
    }

    // Claims tokens and remaining ether balance
    function _claim(
        address _who,
        uint256 _poolId,
        bytes32[] storage _mintProof
    ) internal prank(_who) {
        groupBuy.claim(_poolId, _mintProof);
        _setGlobalState(_poolId, _who);
    }

    // Withdraws pending balance
    function _withdrawBalance(address _who) internal prank(_who) {
        groupBuy.withdrawBalance();
        _setGlobalState(currentId, _who);
    }

    // Sets state of global storage
    function _setGlobalState(uint256 _poolId, address _user) internal {
        _setPoolInfo(_poolId);
        _setNumBids(_poolId);
        _setNextBidId(_poolId);
        if (nextBidId > 0) _setBidInQueue(_poolId, nextBidId - 1);
        _setFilledQuantity(_poolId);
        _setMinReservePrice(_poolId);
        _setTotalContribution(_poolId);
        _setUserContribution(_poolId, _user);
    }

    /// Sets state for currentId
    function _setCurrentId() internal {
        currentId = groupBuy.currentId();
    }

    /// Sets state for pool info
    function _setPoolInfo(uint256 _poolId) internal {
        (nftContract, totalSupply, terminationPeriod, success, nftMerkleRoot) = groupBuy.poolInfo(
            _poolId
        );
    }

    /// Sets state for bid in queue
    function _setBidInQueue(uint256 _poolId, uint256 _bidId) internal {
        (bidId, owner, price, quantity) = groupBuy.getBidInQueue(_poolId, _bidId);
    }

    /// Sets state for filled quantity
    function _setFilledQuantity(uint256 _poolId) internal {
        filledQuantity = groupBuy.filledQuantities(_poolId);
    }

    /// Sets state for min reserve price
    function _setMinReservePrice(uint256 _poolId) internal {
        minReservePrice = (filledQuantity == 0) ? MIN_PRICE : groupBuy.getMinPrice(_poolId);
    }

    /// Sets state for nextBidId
    function _setNextBidId(uint256 _poolId) internal {
        nextBidId = groupBuy.getNextBidId(_poolId);
    }

    /// Sets state for numBids
    function _setNumBids(uint256 _poolId) internal {
        numBids = groupBuy.getNumBids(_poolId);
    }

    /// Sets state for punk offer
    function _setPunkOffer(uint256 _punkId) internal {
        (isForSale, , seller, minValue, ) = punks.punksOfferedForSale(_punkId);
    }

    /// Sets state for total contribution amount
    function _setTotalContribution(uint256 _poolId) internal {
        totalContribution = groupBuy.totalContributions(_poolId);
    }

    /// Sets state for user contribution amount
    function _setUserContribution(uint256 _poolId, address _user) internal {
        userContribution = groupBuy.userContributions(_poolId, _user);
    }

    /// Sets state for bidIds of all users
    function _setBidIds(uint256 _poolId) internal {
        aliceBidIds = groupBuy.getOwnerToBidIds(currentId, alice);
        bobBidIds = groupBuy.getOwnerToBidIds(currentId, bob);
        eveBidIds = groupBuy.getOwnerToBidIds(currentId, eve);
    }

    /// Sets state for a bidId
    function _setBidValues(uint256 _poolId, uint256 _bidId) internal {
        (bidId, owner, price, quantity) = groupBuy.getBidInQueue(_poolId, _bidId);
    }

    /// Sets state for contribution values
    function _setContributionValues(uint256 _poolId) internal {
        filledQuantity = groupBuy.filledQuantities(_poolId);
        minReservePrice = groupBuy.getMinPrice(_poolId);
        totalContribution = groupBuy.totalContributions(_poolId);
        aliceContribution = groupBuy.userContributions(_poolId, alice);
        bobContribution = groupBuy.userContributions(_poolId, bob);
        eveContribution = groupBuy.userContributions(_poolId, eve);
    }

    /// Generates merkle root from list of tokenIds
    function _generateRoot(uint256[] storage _tokenIds) internal view returns (bytes32) {
        uint256 length = _tokenIds.length;
        bytes32[] memory leaves = new bytes32[](length);
        unchecked {
            for (uint256 i; i < length; ++i) {
                leaves[i] = keccak256(abi.encode(_tokenIds[i]));
            }
        }

        return getRoot(leaves);
    }

    /// Increases block time by duration
    function _increaseTime(uint256 _duration) internal {
        vm.warp(block.timestamp + _duration);
    }

    /// Decreases block time by duration
    function _decreaseTime(uint256 _duration) internal {
        vm.warp(block.timestamp - _duration);
    }

    /// Bounds unit price between range
    function _boundPrice(uint256 _price) internal view returns (uint256 unitPrice) {
        unitPrice = bound(_price, MIN_PRICE, MAX_PRICE);
        vm.assume(unitPrice >= MIN_PRICE && unitPrice <= MAX_PRICE);
    }

    /// Bounds quantity of raes between range
    function _boundQuantity(uint256 _quantity, uint256 _supply)
        internal
        view
        returns (uint256 amount)
    {
        amount = bound(_quantity, MIN_SUPPLY, _supply);
        vm.assume(amount >= MIN_SUPPLY && amount <= _supply);
    }

    /// Bounds total supply between range
    function _boundSupply(uint256 _amount) internal view returns (uint256 amount) {
        amount = bound(_amount, MIN_SUPPLY, MAX_SUPPLY);
        vm.assume(amount >= MIN_SUPPLY && amount <= MAX_SUPPLY);
    }

    /// Bounds termination period between range
    function _boundTermination(uint256 _duration) internal view returns (uint256 duration) {
        duration = bound(_duration, MIN_TIME, MAX_TIME);
        vm.assume(duration > MIN_TIME && duration <= MAX_TIME);
    }
}
