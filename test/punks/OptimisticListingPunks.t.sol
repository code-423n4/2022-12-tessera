// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.13;

import "./PunksTestUtil.t.sol";

// USER ROLES
// Deployer: OptimisticListingPunksTest => address(this)
// Vaulter: Alice => address(111)
// Proposer: Bob => address(222)
// Rejector: Eve => address(333)
// Buyer: Susan => address(444)
contract OptimisticListingPunksTest is PunksTestUtil {
    // Listing
    address proposer;
    uint256 collateral;
    uint256 pricePerToken;
    uint256 proposalDate;

    // Offer
    bool isForSale;
    address seller;
    uint256 minValue;

    // Storage
    uint256 etherPayment;
    uint256 listingPrice;
    uint256 lowerPrice;
    uint256 rejectionAmount;

    // Constants
    uint256 constant MIN_BOUND = 1;
    uint256 constant MAX_BOUND = type(uint256).max;
    uint256 constant MAX_PRICE = 10 ether;

    // Errors
    bytes ERC1155_AUTHORIZE_ERROR = bytes("NOT_AUTHORIZED");
    bytes4 ALREADY_REGISTERED_ERROR = IOptimisticListingPunks.AlreadyRegistered.selector;
    bytes4 ALREADY_SETTLED_ERROR = IOptimisticListingPunks.AlreadySettled.selector;
    bytes4 INSUFFICIENT_COLLATERAL_ERROR = IOptimisticListingPunks.InsufficientCollateral.selector;
    bytes4 INVALID_PAYMENT_ERROR = IOptimisticListingPunks.InvalidPayment.selector;
    bytes4 NOT_AUTHORIZED_ERROR = IVault.NotAuthorized.selector;
    bytes4 NOT_ENOUGH_TOKENS_ERROR = IOptimisticListingPunks.NotEnoughTokens.selector;
    bytes4 NOT_LOWER_ERROR = IOptimisticListingPunks.NotLower.selector;
    bytes4 NOT_OWNER_ERROR = IOptimisticListingPunks.NotOwner.selector;
    bytes4 NOT_PROPOSER_ERROR = IOptimisticListingPunks.NotProposer.selector;
    bytes4 NOT_SETTLED_ERROR = IOptimisticListingPunks.NotSettled.selector;
    bytes4 NOT_SOLD_ERROR = IOptimisticListingPunks.NotSold.selector;
    bytes4 NOT_VAULT_ERROR = IOptimisticListingPunks.NotVault.selector;
    bytes4 REJECTED_ERROR = IOptimisticListingPunks.Rejected.selector;
    bytes4 TIME_NOT_ELAPSED_ERROR = IOptimisticListingPunks.TimeNotElapsed.selector;

    /// =================
    /// ===== SETUP =====
    /// =================
    function setUp() public {
        // base contracts
        _setUpContract();
        _setUpProof();
        // punks contract
        _setOwner(address(this), alice, punkId);
        _setAssigned(address(this));
        // wrapper contract
        _registerProxy(alice);
        _transferPunk(alice, proxy, punkId);
        _wrapPunk(alice, punkId);
        // deploy protoform
        _setWrapperApproval(alice, address(protoform), true);
        _deployVault(alice, punkId, mintProof, unwrapProof);
        // mint assets
        _mintERC20(vault, ERC20_SUPPLY);
        _mintERC721(vault, ERC721_SUPPLY);
        _mintERC1155(vault, ERC1155_SUPPLY);
        // distribute tokens
        _transferToken(alice, bob, token, id, QUARTER_SUPPLY);
        _transferToken(alice, eve, token, id, QUARTER_SUPPLY);
        // approve tokens
        _setTokenApproval(alice, address(optimistic), token, true);
        _setTokenApproval(bob, address(optimistic), token, true);
        _setTokenApproval(eve, address(optimistic), token, true);
        // initialize balances
        _initializeEtherBalance();
        _initializeTokenBalance(token, id);

        vm.label(address(this), "OptimisticListingPunksTest");
    }

    /// ====================
    /// ===== REGISTER =====
    /// ====================
    function testRegister() public {
        // setup
        _setProposalState(vault);
        // expect
        _assertListing(address(optimistic), 0, MAX_BOUND, 0);

        // setup
        _setActiveState(vault);
        // expect
        _assertListing(address(optimistic), 0, MAX_BOUND, 0);
    }

    function testRegisterRevertNotVault() public {
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(this)));
        // execute
        optimistic.register(address(this), punkId, unwrapProof);
    }

    function testRegisterRevertAlreadyRegistered() public {
        // expect
        vm.expectRevert(ALREADY_REGISTERED_ERROR);
        // execute
        optimistic.register(vault, 1, unwrapProof);
    }

    /// ===================
    /// ===== PROPOSE =====
    /// ===================
    function testPropose(uint256 _collateral, uint256 _price) public {
        // setup
        _collateral = _boundCollateral(_collateral, bobTokenBalance);
        _price = _boundPrice(_price);
        // execute
        _propose(bob, vault, _collateral, _price);
        // expect
        _assertListing(bob, _collateral, _price, block.timestamp);
        _assertTokenBalance(bob, token, id, bobTokenBalance - _collateral);
        _assertTokenBalance(address(optimistic), token, id, _collateral);
    }

    function testProposeLower(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        lowerPrice = pricePerToken - 1;
        // execute
        _propose(eve, vault, eveTokenBalance, lowerPrice);
        // expect
        _assertListing(eve, eveTokenBalance, lowerPrice, block.timestamp);
        _assertTokenBalance(eve, token, id, eveTokenBalance - collateral);
    }

    function testProposeRevertNotVault(uint256 _collateral, uint256 _price) public {
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(protoform)));
        // execute
        _propose(bob, address(protoform), _collateral, _price);
    }

    function testProposeRevertNotOwner(uint256 _collateral, uint256 _price) public {
        // setup
        _transferPunk(vault, alice, punkId);
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _propose(bob, vault, _collateral, _price);
    }

    function testProposeRevertNotEnoughTokens(uint256 _collateral, uint256 _price) public {
        // setup
        vm.assume(_collateral > bobTokenBalance);
        // expect
        vm.expectRevert(NOT_ENOUGH_TOKENS_ERROR);
        // execute
        _propose(bob, vault, _collateral, _price);
    }

    function testProposeRevertNotLower(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _price = _boundPrice(_price);
        // expect
        vm.expectRevert(NOT_LOWER_ERROR);
        // execute
        _propose(eve, vault, _collateral, _price);
    }

    function testProposeRevertNoApproval(uint256 _collateral, uint256 _price) public {
        // setup
        _setTokenApproval(bob, address(optimistic), token, false);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _price = _boundPrice(_price);
        // expect
        vm.expectRevert(ERC1155_AUTHORIZE_ERROR);
        // execute
        _propose(bob, vault, _collateral, _price);
    }

    /// ===========================
    /// ===== REJECT PROPOSAL =====
    /// ===========================
    function testRejectProposal(
        uint256 _collateral,
        uint256 _price,
        uint256 _amount
    ) public {
        // setup
        testPropose(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _price = _boundPrice(_price);
        _amount = _boundCollateral(_amount, collateral);
        etherPayment = pricePerToken * _amount;
        // execute
        _rejectProposal(eve, vault, etherPayment, _amount);
        // expect
        assertEq(collateral, _collateral - _amount);
        assertEq(bob.balance, bobEtherBalance + etherPayment);
        assertEq(eve.balance, eveEtherBalance - etherPayment);
        _assertTokenBalance(eve, token, id, eveTokenBalance + _amount);
        _assertTokenBalance(address(optimistic), token, id, collateral);
    }

    function testRejectProposalReset(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        etherPayment = pricePerToken * _collateral;
        // execute
        _rejectProposal(eve, vault, etherPayment, _collateral);
        // expect
        assertEq(bob.balance, bobEtherBalance + etherPayment);
        assertEq(eve.balance, eveEtherBalance - etherPayment);
        _assertTokenBalance(eve, token, id, eveTokenBalance + _collateral);
        _assertTokenBalance(address(optimistic), token, id, 0);
        _assertListing(address(optimistic), 0, MAX_BOUND, 0);
    }

    function testRejectProposalRevertNotVault(
        uint256 _collateral,
        uint256 _price,
        uint256 _amount
    ) public {
        // setup
        testPropose(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _amount = _boundCollateral(_amount, collateral);
        etherPayment = pricePerToken * _amount;
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(protoform)));
        // execute
        _rejectProposal(eve, address(protoform), etherPayment, _amount);
    }

    function testRejectProposalRevertNotOwner(
        uint256 _collateral,
        uint256 _price,
        uint256 _amount
    ) public {
        // setup
        testPropose(_collateral, _price);
        _transferPunk(vault, alice, punkId);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _amount = _boundCollateral(_amount, collateral);
        etherPayment = pricePerToken * _amount;
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _rejectProposal(eve, vault, etherPayment, _amount);
    }

    function testRejectProposalRevertInsufficientCollateral(uint256 _collateral, uint256 _price)
        public
    {
        // setup
        testPropose(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        rejectionAmount = _collateral + 1;
        etherPayment = pricePerToken * rejectionAmount;
        // expect
        vm.expectRevert(INSUFFICIENT_COLLATERAL_ERROR);
        // execute
        _rejectProposal(eve, vault, etherPayment, rejectionAmount);
    }

    function testRejectProposalRevertInvalidPayment(
        uint256 _collateral,
        uint256 _price,
        uint256 _amount
    ) public {
        // setup
        testPropose(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _amount = _boundCollateral(_amount, collateral);
        etherPayment = pricePerToken * _amount - 1;
        // expect
        vm.expectRevert(INVALID_PAYMENT_ERROR);
        // execute
        _rejectProposal(eve, vault, etherPayment, _amount);
    }

    /// =========================
    /// ===== REJECT ACTIVE =====
    /// =========================
    function testRejectActive(
        uint256 _collateral,
        uint256 _price,
        uint256 _amount
    ) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _amount = _boundCollateral(_amount, collateral);
        etherPayment = pricePerToken * _amount;
        // execute
        _rejectActive(eve, vault, etherPayment, _amount, delistProof);
        // expect
        assertEq(collateral, _collateral - _amount);
        assertEq(bob.balance, bobEtherBalance + etherPayment);
        assertEq(eve.balance, eveEtherBalance - etherPayment);
        _assertTokenBalance(eve, token, id, eveTokenBalance + _amount);
        _assertTokenBalance(address(optimistic), token, id, collateral);
    }

    function testRejectActiveReset(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        etherPayment = pricePerToken * collateral;
        // execute
        _rejectActive(eve, vault, etherPayment, collateral, delistProof);
        // expect
        assertEq(bob.balance, bobEtherBalance + etherPayment);
        assertEq(eve.balance, eveEtherBalance - etherPayment);
        _assertListing(address(optimistic), 0, MAX_BOUND, 0);
        _assertOffer(false, adapter, 0);
        _assertPunkOwner(vault, punkId);
        _assertTokenBalance(eve, token, id, eveTokenBalance + _collateral);
        _assertTokenBalance(address(optimistic), token, id, collateral);
    }

    function testRejectActiveRevertNotVault(
        uint256 _collateral,
        uint256 _price,
        uint256 _amount
    ) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _amount = _boundCollateral(_amount, collateral);
        etherPayment = pricePerToken * _amount;
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(protoform)));
        // execute
        _rejectActive(eve, address(protoform), etherPayment, _amount, delistProof);
    }

    function testRejectActiveRevertNotOwner(
        uint256 _collateral,
        uint256 _price,
        uint256 _amount
    ) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        _transferPunk(adapter, alice, punkId);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _amount = _boundCollateral(_amount, collateral);
        etherPayment = pricePerToken * _amount;
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _rejectActive(eve, vault, etherPayment, _amount, delistProof);
    }

    function testRejectActiveRevertInsufficientCollateral(uint256 _collateral, uint256 _price)
        public
    {
        // setup
        _setUpActiveListing(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        rejectionAmount = _collateral + 1;
        etherPayment = pricePerToken * rejectionAmount;
        // expect
        vm.expectRevert(INSUFFICIENT_COLLATERAL_ERROR);
        // execute
        _rejectActive(eve, vault, etherPayment, rejectionAmount, delistProof);
    }

    function testRejectActiveRevertInvalidPayment(
        uint256 _collateral,
        uint256 _price,
        uint256 _amount
    ) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _amount = _boundCollateral(_amount, collateral);
        etherPayment = pricePerToken * _amount - 1;
        // expect
        vm.expectRevert(INVALID_PAYMENT_ERROR);
        // execute
        _rejectActive(eve, vault, etherPayment, _amount, delistProof);
    }

    function testRejectActiveRevertInvalidProof(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        etherPayment = pricePerToken * collateral;
        // execute
        vm.expectRevert(
            abi.encodeWithSelector(
                NOT_AUTHORIZED_ERROR,
                address(optimistic),
                address(marketplace),
                IPunksMarketLister.delist.selector
            )
        );
        // execute
        _rejectActive(eve, vault, etherPayment, collateral, listProof);
    }

    /// ================
    /// ===== LIST =====
    /// ================
    function testList(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        _collateral = _boundCollateral(_collateral, bobTokenBalance);
        _price = _boundPrice(_price);
        listingPrice = pricePerToken * IRae(token).totalSupply(id);
        // execute
        _list(bob, vault, transferPunkProof, listProof);
        // expect
        _assertListing(bob, _collateral, _price, block.timestamp - PROPOSAL_PERIOD);
        _assertOffer(true, adapter, listingPrice);
        _assertPunkOwner(adapter, punkId);
        _setProposalState(vault);
        _assertListing(address(optimistic), 0, MAX_BOUND, 0);
    }

    function testListLower() public {
        // setup
        rejectionAmount = 5;
        pricePerToken = 2 ether;
        etherPayment = rejectionAmount * pricePerToken;
        _propose(bob, vault, bobTokenBalance, pricePerToken);
        _rejectProposal(eve, vault, etherPayment, rejectionAmount);
        _increaseTime(PROPOSAL_PERIOD);
        // execute
        _list(bob, vault, transferPunkProof, listProof);
        // expect
        assertEq(eve.balance, eveEtherBalance - etherPayment);
        _assertListing(
            bob,
            bobTokenBalance - rejectionAmount,
            pricePerToken,
            block.timestamp - PROPOSAL_PERIOD
        );
        _assertPunkOwner(adapter, punkId);
        _assertTokenBalance(bob, token, id, 0);
        _assertTokenBalance(eve, token, id, eveTokenBalance + rejectionAmount);

        // setup
        lowerPrice = 1 ether;
        _rejectActive(eve, vault, etherPayment, rejectionAmount, delistProof);
        _propose(alice, vault, aliceTokenBalance, lowerPrice);
        _increaseTime(PROPOSAL_PERIOD);
        // execute
        _list(alice, vault, transferPunkProof, listProof);
        // expect
        assertEq(eve.balance, eveEtherBalance - (etherPayment * 2));
        assertEq(optimistic.pendingBalances(vault, bob), bobTokenBalance - (rejectionAmount * 2));
        _assertListing(alice, aliceTokenBalance, lowerPrice, block.timestamp - PROPOSAL_PERIOD);
        _assertPunkOwner(adapter, punkId);
        _assertTokenBalance(alice, token, id, 0);
        _assertTokenBalance(bob, token, id, 0);
        _assertTokenBalance(eve, token, id, eveTokenBalance + (rejectionAmount * 2));
    }

    function testListRevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(protoform)));
        // execute
        _list(bob, address(protoform), transferPunkProof, listProof);
    }

    function testListRevertNotOwner(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        _transferPunk(vault, alice, punkId);
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _list(bob, vault, transferPunkProof, listProof);
    }

    function testListRevertRejected(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        etherPayment = pricePerToken * collateral;
        _rejectProposal(eve, vault, etherPayment, collateral);
        // expect
        vm.expectRevert(REJECTED_ERROR);
        // execute
        _list(bob, vault, transferPunkProof, listProof);
    }

    function testListRevertTimeNotElapsed(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD - 1);
        // expect
        vm.expectRevert(TIME_NOT_ELAPSED_ERROR);
        // execute
        _list(bob, vault, transferPunkProof, listProof);
    }

    function testListRevertInvalidTransferProof(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        // expect
        vm.expectRevert(
            abi.encodeWithSelector(
                NOT_AUTHORIZED_ERROR,
                address(optimistic),
                address(marketplace),
                IPunksMarketLister.transferPunk.selector
            )
        );
        // execute
        _list(bob, vault, ethTransferProof, listProof);
    }

    function testListRevertInvalidListProof(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        // expect
        vm.expectRevert(
            abi.encodeWithSelector(
                NOT_AUTHORIZED_ERROR,
                address(optimistic),
                address(marketplace),
                IPunksMarketLister.list.selector
            )
        );
        // execute
        _list(bob, vault, transferPunkProof, delistProof);
    }

    /// ==================
    /// ===== CANCEL =====
    /// ==================
    function testCancel(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        // execute
        _cancel(bob, vault, delistProof);
        // expect
        _assertListing(address(optimistic), 0, MAX_BOUND, 0);
        _assertOffer(false, adapter, 0);
        _assertPunkOwner(vault, punkId);
        _assertTokenBalance(bob, token, id, bobTokenBalance);
        _assertTokenBalance(address(optimistic), token, id, collateral);
    }

    function testCancelRevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(protoform)));
        // execute
        _cancel(bob, address(protoform), delistProof);
    }

    function testCancelRevertNotOwner(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        _transferPunk(adapter, alice, punkId);
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _cancel(bob, vault, delistProof);
    }

    function testCancelRevertNotProposer(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        // expect
        vm.expectRevert(NOT_PROPOSER_ERROR);
        // execute
        _cancel(eve, vault, delistProof);
    }

    function testCancelRevertInvalidProof(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        // expect
        vm.expectRevert(
            abi.encodeWithSelector(
                NOT_AUTHORIZED_ERROR,
                address(optimistic),
                address(marketplace),
                IPunksMarketLister.delist.selector
            )
        );
        // execute
        _cancel(bob, vault, listProof);
    }

    /// ==================
    /// ===== SETTLE =====
    /// ==================
    function testSettle(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpSettle(_collateral, _price);
        // execute
        _settle(bob, vault, withdrawProof);
        // expect
        assertEq(collateral, 0);
        assertEq(susan.balance, susanEtherBalance - listingPrice);
        assertEq(address(optimistic).balance, listingPrice);
        _assertOffer(false, susan, 0);
    }

    function testSettleRevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpSettle(_collateral, _price);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(protoform)));
        // execute
        _settle(bob, address(protoform), withdrawProof);
    }

    function testSettleRevertNotSold(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        // expect
        vm.expectRevert(NOT_SOLD_ERROR);
        // execute
        _settle(bob, vault, withdrawProof);
    }

    function testSettleRevertAlreadySettled(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpSettle(_collateral, _price);
        _settle(bob, vault, withdrawProof);
        // expect
        vm.expectRevert(ALREADY_SETTLED_ERROR);
        // execute
        _settle(alice, vault, withdrawProof);
    }

    function testSettleRevertInvalidProof(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpSettle(_collateral, _price);
        // expect
        vm.expectRevert(
            abi.encodeWithSelector(
                NOT_AUTHORIZED_ERROR,
                address(optimistic),
                address(marketplace),
                IPunksMarketLister.withdraw.selector
            )
        );
        // execute
        _settle(alice, vault, burnProof);
    }

    /// ================
    /// ===== CASH =====
    /// ================
    function testCash(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpCash(_collateral, _price);
        // execute
        _cash(alice, vault, burnProof);
        _cash(bob, vault, burnProof);
        _cash(eve, vault, burnProof);
        // expect
        assertEq(alice.balance, aliceEtherBalance + (aliceTokenBalance * pricePerToken));
        assertEq(bob.balance, bobEtherBalance + (bobTokenBalance * pricePerToken));
        assertEq(eve.balance, eveEtherBalance + (eveTokenBalance * pricePerToken));
        _assertTokenBalance(alice, token, id, 0);
        _assertTokenBalance(bob, token, id, 0);
        _assertTokenBalance(eve, token, id, 0);
        _assertTokenBalance(address(optimistic), token, id, 0);
    }

    function testCashRevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpCash(_collateral, _price);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(protoform)));
        // execute
        _cash(bob, address(protoform), burnProof);
    }

    function testCashRevertNotSold(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        _list(bob, vault, transferPunkProof, listProof);
        // expect
        vm.expectRevert(NOT_SOLD_ERROR);
        // execute
        _cash(bob, vault, burnProof);
    }

    function testCashRevertNotSettled(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        _list(bob, vault, transferPunkProof, listProof);
        _buyPunk(alice, punkId, minValue);
        // expect
        vm.expectRevert(NOT_SETTLED_ERROR);
        // execute
        _cash(bob, vault, burnProof);
    }

    function testCashRevertNotEnoughTokens(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpCash(_collateral, _price);
        _cash(bob, vault, burnProof);
        // expect
        vm.expectRevert(NOT_ENOUGH_TOKENS_ERROR);
        // execute
        _cash(bob, vault, burnProof);
    }

    function testCashRevertInvalidProof(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpCash(_collateral, _price);
        // expect
        vm.expectRevert(
            abi.encodeWithSelector(
                NOT_AUTHORIZED_ERROR,
                address(optimistic),
                address(supply),
                ISupply.burn.selector
            )
        );
        // execute
        _cash(bob, vault, withdrawProof);
    }

    /// ===============================
    /// ===== WITHDRAW COLLATERAL =====
    /// ===============================
    function testWithdrawCollateral(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        lowerPrice = pricePerToken - 1;
        _propose(eve, vault, eveTokenBalance, lowerPrice);
        // execute
        _withdrawCollateral(bob, vault, bob);
        // expect
        _assertTokenBalance(bob, token, id, bobTokenBalance);
    }

    function testWithdrawCollateralRevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        lowerPrice = pricePerToken - 1;
        _propose(eve, vault, eveTokenBalance, lowerPrice);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(protoform)));
        // execute
        _withdrawCollateral(bob, address(protoform), bob);
    }

    function testWithdrawCollateralRevertNotEnoughTokens(uint256 _collateral, uint256 _price)
        public
    {
        // setup
        testPropose(_collateral, _price);
        lowerPrice = pricePerToken - 1;
        _propose(eve, vault, eveTokenBalance, lowerPrice);
        _withdrawCollateral(bob, vault, bob);
        // expect
        vm.expectRevert(NOT_ENOUGH_TOKENS_ERROR);
        // execute
        _withdrawCollateral(bob, vault, bob);
    }

    /// ==========================
    /// ===== WITHDRAW ETHER =====
    /// ==========================
    function testWithdrawEther(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // execute
        _withdrawEther(susan, vault, susan, ethTransferProof);
        // expect
        assertEq(vault.balance, 0);
        assertEq(susan.balance, susanEtherBalance + vaultEtherBalance - listingPrice);
    }

    function testWithdrawEtherRevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(protoform)));
        // execute
        _withdrawEther(susan, address(protoform), susan, ethTransferProof);
    }

    function testWithdrawEtherRevertNotOwner(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _withdrawEther(eve, vault, eve, ethTransferProof);
    }

    function testWithdrawEtherRevertInvalidProof(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // expect
        vm.expectRevert(
            abi.encodeWithSelector(
                NOT_AUTHORIZED_ERROR,
                address(optimistic),
                address(transfer),
                ITransfer.ETHTransfer.selector
            )
        );
        // execute
        _withdrawEther(susan, vault, susan, erc20TransferProof);
    }

    /// ==========================
    /// ===== WITHDRAW ERC20 =====
    /// ==========================
    function testWithdrawERC20(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // execute
        _withdrawERC20(susan, vault, susan, address(erc20), ERC20_SUPPLY, erc20TransferProof);
        // expect
        assertEq(erc20.balanceOf(susan), ERC20_SUPPLY);
        assertEq(erc20.balanceOf(vault), 0);
    }

    function testWithdrawERC20RevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(protoform)));
        // execute
        _withdrawERC20(
            susan,
            address(protoform),
            susan,
            address(erc20),
            ERC20_SUPPLY,
            erc20TransferProof
        );
    }

    function testWithdrawERC20RevertNotOwner(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _withdrawERC20(eve, vault, eve, address(erc20), ERC20_SUPPLY, erc20TransferProof);
    }

    function testWithdrawERC20RevertInvalidProof(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // expect
        vm.expectRevert(
            abi.encodeWithSelector(
                NOT_AUTHORIZED_ERROR,
                address(optimistic),
                address(transfer),
                ITransfer.ERC20Transfer.selector
            )
        );
        // execute
        _withdrawERC20(susan, vault, susan, address(erc20), ERC20_SUPPLY, ethTransferProof);
    }

    /// ===========================
    /// ===== WITHDRAW ERC721 =====
    /// ===========================
    function testWithdrawERC721(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // execute
        for (uint256 i; i < ERC721_SUPPLY; ++i) {
            _withdrawERC721(susan, vault, susan, address(erc721), i, erc721TransferProof);
        }
        // expect
        assertEq(erc721.balanceOf(vault), 0);
        for (uint256 i; i < ERC721_SUPPLY; ++i) {
            assertEq(erc721.ownerOf(i), susan);
        }
    }

    function testWithdrawERC721RevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(protoform)));
        // execute
        _withdrawERC721(susan, address(protoform), susan, address(erc721), 0, erc721TransferProof);
    }

    function testWithdrawERC721RevertNotOwner(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _withdrawERC721(eve, vault, eve, address(erc721), 0, erc721TransferProof);
    }

    function testWithdrawERC721RevertInvalidProof(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // expect
        vm.expectRevert(
            abi.encodeWithSelector(
                NOT_AUTHORIZED_ERROR,
                address(optimistic),
                address(transfer),
                ITransfer.ERC721TransferFrom.selector
            )
        );
        // execute
        _withdrawERC721(susan, vault, susan, address(erc721), 0, erc1155TransferProof);
    }

    /// ============================
    /// ===== WITHDRAW ERC1155 =====
    /// ============================
    function testWithdrawERC1155(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // execute
        for (uint256 i; i < ERC1155_SUPPLY; ++i) {
            _withdrawERC1155(
                susan,
                vault,
                susan,
                address(erc1155),
                i,
                ERC1155_SUPPLY,
                erc1155TransferProof
            );
        }
        // expect
        for (uint256 i; i < ERC1155_SUPPLY; ++i) {
            assertEq(erc1155.balanceOf(susan, i), ERC1155_SUPPLY);
            assertEq(erc1155.balanceOf(vault, i), 0);
        }
    }

    function testWithdrawERC1155RevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(protoform)));
        // execute
        _withdrawERC1155(
            susan,
            address(protoform),
            susan,
            address(erc1155),
            0,
            ERC1155_SUPPLY,
            erc1155TransferProof
        );
    }

    function testWithdrawERC1155RevertNotOwner(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _withdrawERC1155(
            eve,
            vault,
            eve,
            address(erc1155),
            0,
            ERC1155_SUPPLY,
            erc1155TransferProof
        );
    }

    function testWithdrawERC1155RevertInvalidProof(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpWithdraw(_collateral, _price);
        // expect
        vm.expectRevert(
            abi.encodeWithSelector(
                NOT_AUTHORIZED_ERROR,
                address(optimistic),
                address(transfer),
                ITransfer.ERC1155TransferFrom.selector
            )
        );
        // execute
        _withdrawERC1155(
            susan,
            vault,
            susan,
            address(erc1155),
            0,
            ERC1155_SUPPLY,
            erc721TransferProof
        );
    }

    /// ===================
    /// ===== HELPERS =====
    /// ===================

    /// Setup for executing active listing
    function _setUpActiveListing(uint256 _collateral, uint256 _price) internal {
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        _list(bob, vault, transferPunkProof, listProof);
    }

    /// Setup for settling sale of punk
    function _setUpSettle(uint256 _collateral, uint256 _price) internal {
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        _list(bob, vault, transferPunkProof, listProof);
        _buyPunk(susan, punkId, minValue);
    }

    /// Setup for cashing out from sale
    function _setUpCash(uint256 _collateral, uint256 _price) internal {
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        _list(bob, vault, transferPunkProof, listProof);
        _buyPunk(susan, punkId, minValue);
        _settle(eve, vault, withdrawProof);
        _withdrawCollateral(bob, vault, bob);
    }

    /// Setup for withdrawing assets from vault
    function _setUpWithdraw(uint256 _collateral, uint256 _price) internal {
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        _list(bob, vault, transferPunkProof, listProof);
        _buyPunk(susan, punkId, minValue);
        _settle(eve, vault, withdrawProof);
    }

    /// Proposes new listing
    function _propose(
        address _who,
        address _vault,
        uint256 _collateral,
        uint256 _price
    ) internal prank(_who) {
        optimistic.propose(_vault, _collateral, _price);
        _setProposalState(_vault);
    }

    /// Rejects proposed listing
    function _rejectProposal(
        address _who,
        address _vault,
        uint256 _payment,
        uint256 _amount
    ) internal prank(_who) {
        optimistic.rejectProposal{value: _payment}(_vault, _amount);
        _setProposalState(_vault);
    }

    /// Rejects active listing
    function _rejectActive(
        address _who,
        address _vault,
        uint256 _payment,
        uint256 _amount,
        bytes32[] storage _delistProof
    ) internal prank(_who) {
        optimistic.rejectActive{value: _payment}(_vault, _amount, _delistProof);
        _setActiveState(_vault);
        _setOfferState(optimistic.vaultToPunk(_vault));
    }

    /// Executes active listing
    function _list(
        address _who,
        address _vault,
        bytes32[] storage _transferPunkProof,
        bytes32[] storage _listProof
    ) internal prank(_who) {
        optimistic.list(_vault, _transferPunkProof, _listProof);
        _setActiveState(_vault);
        _setOfferState(optimistic.vaultToPunk(_vault));
    }

    /// Cancels active listing
    function _cancel(
        address _who,
        address _vault,
        bytes32[] storage _delistProof
    ) internal prank(_who) {
        optimistic.cancel(_vault, _delistProof);
        _setActiveState(_vault);
        _setOfferState(optimistic.vaultToPunk(_vault));
    }

    /// Buys punk listed for sale
    function _buyPunk(
        address _buyer,
        uint256 _punkId,
        uint256 _payment
    ) internal prank(_buyer) {
        punks.buyPunk{value: _payment}(_punkId);
    }

    /// Settles sale of active listing
    function _settle(
        address _who,
        address _vault,
        bytes32[] storage _withdrawProof
    ) internal prank(_who) {
        optimistic.settle(_vault, _withdrawProof);
        listingPrice = minValue;
        _setActiveState(_vault);
        _setOfferState(optimistic.vaultToPunk(_vault));
    }

    /// Cashes out from sale
    function _cash(
        address _who,
        address _vault,
        bytes32[] storage _burnProof
    ) internal prank(_who) {
        optimistic.cash(_vault, _burnProof);
    }

    /// Withdraws collateral from module
    function _withdrawCollateral(
        address _who,
        address _vault,
        address _to
    ) internal prank(_who) {
        optimistic.withdrawCollateral(_vault, _to);
    }

    /// Withdraws ether from vault
    function _withdrawEther(
        address _who,
        address _vault,
        address _to,
        bytes32[] storage _ethTransferProof
    ) internal prank(_who) {
        optimistic.withdrawEther(_vault, _to, _ethTransferProof);
    }

    /// Withdraws ERC20 token from vault
    function _withdrawERC20(
        address _who,
        address _vault,
        address _to,
        address _token,
        uint256 _amount,
        bytes32[] storage _erc20TransferProof
    ) internal prank(_who) {
        optimistic.withdrawERC20(_vault, _to, _token, _amount, _erc20TransferProof);
    }

    /// Withdraws ERC721 token from vault
    function _withdrawERC721(
        address _who,
        address _vault,
        address _to,
        address _token,
        uint256 _tokenId,
        bytes32[] storage _erc721TransferProof
    ) internal prank(_who) {
        optimistic.withdrawERC721(_vault, _to, _token, _tokenId, _erc721TransferProof);
    }

    /// Withdraws ERC1155 token from vault
    function _withdrawERC1155(
        address _who,
        address _vault,
        address _to,
        address _token,
        uint256 _id,
        uint256 _amount,
        bytes32[] storage _erc1155TransferProof
    ) internal prank(_who) {
        optimistic.withdrawERC1155(_vault, _to, _token, _id, _amount, _erc1155TransferProof);
    }

    /// Sets state for active listing
    function _setActiveState(address _vault) internal {
        (proposer, collateral, pricePerToken, proposalDate) = optimistic.activeListings(_vault);
    }

    /// Sets state for proposed listing
    function _setProposalState(address _vault) internal {
        (proposer, collateral, pricePerToken, proposalDate) = optimistic.proposedListings(_vault);
    }

    /// Sets state for punk offer
    function _setOfferState(uint256 _punkId) internal {
        (isForSale, , seller, minValue, ) = punks.punksOfferedForSale(_punkId);
    }

    /// Checks current state of listing
    function _assertListing(
        address _proposer,
        uint256 _collateral,
        uint256 _pricePerToken,
        uint256 _proposalDate
    ) internal {
        assertEq(proposer, _proposer);
        assertEq(collateral, _collateral);
        assertEq(pricePerToken, _pricePerToken);
        assertEq(proposalDate, _proposalDate);
    }

    /// Checks current state of punk offer
    function _assertOffer(
        bool _isForSale,
        address _seller,
        uint256 _minValue
    ) internal {
        assertEq(isForSale, _isForSale);
        assertEq(seller, _seller);
        assertEq(minValue, _minValue);
    }

    /// Bounds collateral amount between range
    function _boundCollateral(uint256 _collateral, uint256 _maxBound)
        internal
        view
        returns (uint256 amount)
    {
        amount = bound(_collateral, MIN_BOUND, _maxBound);
        vm.assume(amount >= MIN_BOUND && amount <= _maxBound);
    }

    /// Bounds price per token between range
    function _boundPrice(uint256 _price) internal view returns (uint256 price) {
        price = bound(_price, MIN_BOUND, MAX_PRICE);
        vm.assume(price >= MIN_BOUND && price < MAX_PRICE);
    }
}
