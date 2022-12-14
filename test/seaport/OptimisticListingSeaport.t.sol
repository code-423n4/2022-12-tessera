// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.13;

import "./SeaportTestUtil.t.sol";

// USER ROLES
// Deployer: OptimisticListingSeaportTest => address(this)
// Vaulter: Alice => address(111)
// Proposer: Bob => address(222)
// Rejector: Eve => address(333)
// Buyer: Susan => address(444)
contract OptimisticListingSeaportTest is SeaportTestUtil {
    // Listing
    address public proposer;
    uint256 public collateral;
    uint256 public pricePerToken;
    uint256 public proposalDate;
    Order public order;

    // Offer items
    OfferItem[] public offer;

    // Offer
    bool isValidated;
    bool isCancelled;
    uint256 totalFilled;
    uint256 totalSize;

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
    bytes4 INSUFFICIENT_COLLATERAL_ERROR =
        IOptimisticListingSeaport.InsufficientCollateral.selector;
    bytes4 INVALID_PAYMENT_ERROR = IOptimisticListingSeaport.InvalidPayment.selector;
    bytes4 NOT_AUTHORIZED_ERROR = IVault.NotAuthorized.selector;
    bytes4 NOT_ENOUGH_TOKENS_ERROR = IOptimisticListingSeaport.NotEnoughTokens.selector;
    bytes4 NOT_LOWER_ERROR = IOptimisticListingSeaport.NotLower.selector;
    bytes4 NOT_OWNER_ERROR = IOptimisticListingSeaport.NotOwner.selector;
    bytes4 NOT_PROPOSER_ERROR = IOptimisticListingSeaport.NotProposer.selector;
    bytes4 NOT_SOLD_ERROR = IOptimisticListingSeaport.NotSold.selector;
    bytes4 NOT_VAULT_ERROR = IOptimisticListingSeaport.NotVault.selector;
    bytes4 REJECTED_ERROR = IOptimisticListingSeaport.Rejected.selector;
    bytes4 TIME_NOT_ELAPSED_ERROR = IOptimisticListingSeaport.TimeNotElapsed.selector;

    /// =================
    /// ===== SETUP =====
    /// =================
    function setUp() public {
        // base contracts
        setUpContract();
        // deploy vault
        deployBaseVault(alice);
        // distribute tokens
        _transferToken(alice, bob, token, tokenId, QUARTER_SUPPLY);
        _transferToken(alice, eve, token, tokenId, QUARTER_SUPPLY);
        // approve tokens
        _setTokenApproval(alice, address(optimistic), token, true);
        _setTokenApproval(bob, address(optimistic), token, true);
        _setTokenApproval(eve, address(optimistic), token, true);
        // initialize balances
        _initializeEtherBalance();
        _initializeTokenBalance(token, tokenId);
        // construct Seaport order
        _buildOffer();

        vm.label(address(this), "OptimisticListingSeaportTest");
    }

    /// ===================
    /// ===== PROPOSE =====
    /// ===================
    function testPropose(uint256 _collateral, uint256 _price) public {
        // setup
        _collateral = _boundCollateral(_collateral, bobTokenBalance);
        _price = _boundPrice(_price);
        // execute
        _propose(bob, vault, _collateral, _price, offer);
        // expect
        _assertListing(bob, _collateral, _price, block.timestamp);
        _assertTokenBalance(bob, token, tokenId, bobTokenBalance - _collateral);
        _assertTokenBalance(address(optimistic), token, tokenId, _collateral);
    }

    function testProposeLower(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        lowerPrice = pricePerToken - 1;
        // execute
        _propose(eve, vault, eveTokenBalance, lowerPrice, offer);
        // expect
        _assertListing(eve, eveTokenBalance, lowerPrice, block.timestamp);
        _assertTokenBalance(eve, token, tokenId, eveTokenBalance - collateral);
    }

    function testProposeRevertNotVault(uint256 _collateral, uint256 _price) public {
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(baseVault)));
        // execute
        _propose(bob, address(baseVault), _collateral, _price, offer);
    }

    function testProposeRevertNotOwner(uint256 _collateral, uint256 _price) public {
        testList(_collateral, _price);
        _fulfillOrder(susan, vault);
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _propose(bob, vault, _collateral, _price, offer);
    }

    function testProposeRevertNotEnoughTokens(uint256 _collateral, uint256 _price) public {
        // setup
        vm.assume(_collateral > bobTokenBalance);
        // expect
        vm.expectRevert(NOT_ENOUGH_TOKENS_ERROR);
        // execute
        _propose(bob, vault, _collateral, _price, offer);
    }

    function testProposeRevertNotLower(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _price = _boundPrice(_price);
        // expect
        vm.expectRevert(NOT_LOWER_ERROR);
        // execute
        _propose(eve, vault, _collateral, _price, offer);
    }

    function testProposeRevertNoApproval(uint256 _collateral, uint256 _price) public {
        // setup
        _setTokenApproval(bob, address(optimistic), token, false);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _price = _boundPrice(_price);
        // expect
        vm.expectRevert(ERC1155_AUTHORIZE_ERROR);
        // execute
        _propose(bob, vault, _collateral, _price, offer);
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
        // reject proposal
        _rejectProposal(eve, vault, etherPayment, _amount);
        // expect
        assertEq(collateral, _collateral - _amount);
        assertEq(bob.balance, bobEtherBalance + etherPayment);
        assertEq(eve.balance, eveEtherBalance - etherPayment);
        _assertTokenBalance(eve, token, tokenId, eveTokenBalance + _amount);
        _assertTokenBalance(address(optimistic), token, tokenId, collateral);
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
        _assertTokenBalance(eve, token, tokenId, eveTokenBalance + _collateral);
        _assertTokenBalance(address(optimistic), token, tokenId, 0);
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
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(baseVault)));
        // execute
        _rejectProposal(eve, address(baseVault), etherPayment, _amount);
    }

    function testRejectProposalRevertNotOwner(
        uint256 _collateral,
        uint256 _price,
        uint256 _amount
    ) public {
        // setup
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        _list(bob, vault, validateProof);
        _fulfillOrder(susan, vault);
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
        _rejectActive(eve, vault, etherPayment, _amount, cancelProof);
        // expect
        assertEq(collateral, _collateral - _amount);
        assertEq(bob.balance, bobEtherBalance + etherPayment);
        assertEq(eve.balance, eveEtherBalance - etherPayment);
        _assertTokenBalance(eve, token, tokenId, eveTokenBalance + _amount);
        _assertTokenBalance(address(optimistic), token, tokenId, collateral);
    }

    function testRejectActiveReset(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        etherPayment = pricePerToken * collateral;
        // execute
        _rejectActive(eve, vault, etherPayment, collateral, cancelProof);
        // expect
        assertEq(bob.balance, bobEtherBalance + etherPayment);
        assertEq(eve.balance, eveEtherBalance - etherPayment);
        _assertListing(address(optimistic), 0, MAX_BOUND, 0);
        _assertOffer(false, true, 0, 0);
        _assertTokenBalance(eve, token, tokenId, eveTokenBalance + _collateral);
        _assertTokenBalance(address(optimistic), token, tokenId, collateral);
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
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(baseVault)));
        // execute
        _rejectActive(eve, address(baseVault), etherPayment, _amount, cancelProof);
    }

    function testRejectActiveRevertNotOwner(
        uint256 _collateral,
        uint256 _price,
        uint256 _amount
    ) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        // _list(bob, vault, validateProof);
        _fulfillOrder(susan, vault);
        _collateral = _boundCollateral(_collateral, eveTokenBalance);
        _amount = _boundCollateral(_amount, collateral);
        etherPayment = pricePerToken * _amount;
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _rejectActive(eve, vault, etherPayment, _amount, cancelProof);
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
        _rejectActive(eve, vault, etherPayment, rejectionAmount, cancelProof);
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
        _rejectActive(eve, vault, etherPayment, _amount, cancelProof);
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
                address(lister),
                ISeaportLister.cancelListing.selector
            )
        );
        // execute
        _rejectActive(eve, vault, etherPayment, collateral, validateProof);
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
        listingPrice = pricePerToken * IRae(token).totalSupply(tokenId);
        // execute
        _list(bob, vault, validateProof);
        // expect
        _assertListing(bob, _collateral, _price, block.timestamp - PROPOSAL_PERIOD);
        _assertOffer(true, false, 0, 0);
        _assertItemOwnership(vault);
        _setProposalState(vault);
        _assertListing(address(optimistic), 0, MAX_BOUND, 0);
    }

    function testListLower() public {
        // setup
        rejectionAmount = 5;
        pricePerToken = 2 ether;
        etherPayment = rejectionAmount * pricePerToken;
        _propose(bob, vault, bobTokenBalance, pricePerToken, offer);
        _rejectProposal(eve, vault, etherPayment, rejectionAmount);
        _increaseTime(PROPOSAL_PERIOD);
        // execute
        _list(bob, vault, validateProof);
        // expect
        assertEq(eve.balance, eveEtherBalance - etherPayment);
        _assertListing(
            bob,
            bobTokenBalance - rejectionAmount,
            pricePerToken,
            block.timestamp - PROPOSAL_PERIOD
        );
        _assertItemOwnership(vault);
        _assertTokenBalance(bob, token, tokenId, 0);
        _assertTokenBalance(eve, token, tokenId, eveTokenBalance + rejectionAmount);

        // setup
        lowerPrice = 1 ether;
        _rejectActive(eve, vault, etherPayment, rejectionAmount, cancelProof);
        _propose(alice, vault, aliceTokenBalance, lowerPrice, offer);
        _increaseTime(PROPOSAL_PERIOD);
        // execute
        _list(alice, vault, validateProof);
        // expect
        assertEq(eve.balance, eveEtherBalance - (etherPayment * 2));
        assertEq(optimistic.pendingBalances(vault, bob), bobTokenBalance - (rejectionAmount * 2));
        _assertListing(alice, aliceTokenBalance, lowerPrice, block.timestamp - PROPOSAL_PERIOD);
        _assertItemOwnership(vault);
        _assertTokenBalance(alice, token, tokenId, 0);
        _assertTokenBalance(bob, token, tokenId, 0);
        _assertTokenBalance(eve, token, tokenId, eveTokenBalance + (rejectionAmount * 2));
    }

    function testListRevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(baseVault)));
        // execute
        _list(bob, address(baseVault), validateProof);
    }

    function testListRevertNotOwner(uint256 _collateral, uint256 _price) public {
        // setup
        testList(_collateral, _price);
        _fulfillOrder(susan, vault);
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _list(bob, vault, validateProof);
    }

    function testListRevertRejected(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        etherPayment = pricePerToken * collateral;
        _rejectProposal(eve, vault, etherPayment, collateral);
        // expect
        vm.expectRevert(REJECTED_ERROR);
        // execute
        _list(bob, vault, validateProof);
    }

    function testListRevertTimeNotElapsed(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD - 1);
        // expect
        vm.expectRevert(TIME_NOT_ELAPSED_ERROR);
        // execute
        _list(bob, vault, validateProof);
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
                address(lister),
                ISeaportLister.validateListing.selector
            )
        );
        // execute
        _list(bob, vault, cancelProof);
    }

    /// ==================
    /// ===== CANCEL =====
    /// ==================
    function testCancel(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        // execute
        _cancel(bob, vault, cancelProof);
        // expect
        _assertListing(address(optimistic), 0, MAX_BOUND, 0);
        _assertOffer(false, true, 0, 0);
        _assertItemOwnership(vault);
        _assertTokenBalance(bob, token, tokenId, bobTokenBalance);
        _assertTokenBalance(address(optimistic), token, tokenId, collateral);
    }

    function testCancelRevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(baseVault)));
        // execute
        _cancel(bob, address(baseVault), cancelProof);
    }

    function testCancelRevertNotOwner(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        _fulfillOrder(susan, vault);
        // expect
        vm.expectRevert(NOT_OWNER_ERROR);
        // execute
        _cancel(bob, vault, cancelProof);
    }

    function testCancelRevertNotProposer(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        // expect
        vm.expectRevert(NOT_PROPOSER_ERROR);
        // execute
        _cancel(eve, vault, cancelProof);
    }

    function testCancelRevertInvalidProof(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpActiveListing(_collateral, _price);
        // expect
        vm.expectRevert(
            abi.encodeWithSelector(
                NOT_AUTHORIZED_ERROR,
                address(optimistic),
                address(lister),
                ISeaportLister.cancelListing.selector
            )
        );
        // execute
        _cancel(bob, vault, validateProof);
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
        _assertTokenBalance(alice, token, tokenId, 0);
        _assertTokenBalance(bob, token, tokenId, 0);
        _assertTokenBalance(eve, token, tokenId, 0);
        _assertTokenBalance(address(optimistic), token, tokenId, 0);
    }

    function testCashRevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        _setUpCash(_collateral, _price);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(baseVault)));
        // execute
        _cash(bob, address(baseVault), burnProof);
    }

    function testCashRevertNotSold(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        _list(bob, vault, validateProof);
        // expect
        vm.expectRevert(NOT_SOLD_ERROR);
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
                address(supplyTarget),
                ISupply.burn.selector
            )
        );
        // execute
        _cash(bob, vault, validateProof);
    }

    /// ===============================
    /// ===== WITHDRAW COLLATERAL =====
    /// ===============================
    function testWithdrawCollateral(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        lowerPrice = pricePerToken - 1;
        _propose(eve, vault, eveTokenBalance, lowerPrice, offer);
        // execute
        _withdrawCollateral(bob, vault, bob);
        // expect
        _assertTokenBalance(bob, token, tokenId, bobTokenBalance);
    }

    function testWithdrawCollateralRevertNotVault(uint256 _collateral, uint256 _price) public {
        // setup
        testPropose(_collateral, _price);
        lowerPrice = pricePerToken - 1;
        _propose(eve, vault, eveTokenBalance, lowerPrice, offer);
        // expect
        vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_ERROR, address(baseVault)));
        // execute
        _withdrawCollateral(bob, address(baseVault), bob);
    }

    function testWithdrawCollateralRevertNotEnoughTokens(uint256 _collateral, uint256 _price)
        public
    {
        // setup
        testPropose(_collateral, _price);
        lowerPrice = pricePerToken - 1;
        _propose(eve, vault, eveTokenBalance, lowerPrice, offer);
        _withdrawCollateral(bob, vault, bob);
        // expect
        vm.expectRevert(NOT_ENOUGH_TOKENS_ERROR);
        // execute
        _withdrawCollateral(bob, vault, bob);
    }

    /// ===================
    /// ===== HELPERS =====
    /// ===================

    /// Setup for executing active listing
    function _setUpActiveListing(uint256 _collateral, uint256 _price) internal {
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        _list(bob, vault, validateProof);
    }

    /// Checks current state of punk offer
    function _assertOffer(
        bool _isValidated,
        bool _isCancelled,
        uint256 _totalFilled,
        uint256 _totalSize
    ) internal {
        assertEq(isValidated, _isValidated);
        assertEq(isCancelled, _isCancelled);
        assertEq(totalFilled, _totalFilled);
        assertEq(totalSize, _totalSize);
    }

    /// Sets state of the Seaport Order
    function _setOfferState(address _vault) internal {
        (isValidated, isCancelled, totalFilled, totalSize) = ISeaport(SEAPORT).getOrderStatus(
            optimistic.vaultOrderHash(_vault)
        );
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

    /// Bounds collateral amount between range
    function _boundCollateral(uint256 _collateral, uint256 _maxBound)
        internal
        returns (uint256 amount)
    {
        amount = bound(_collateral, MIN_BOUND, _maxBound);
        vm.assume(amount >= MIN_BOUND && amount <= _maxBound);
    }

    /// Bounds price per token between range
    function _boundPrice(uint256 _price) internal returns (uint256 price) {
        price = bound(_price, MIN_BOUND, MAX_PRICE);
        vm.assume(price >= MIN_BOUND && price < MAX_PRICE);
    }

    /// Sets state for active listing
    function _setActiveState(address _vault) internal {
        (
            address proposerState,
            uint256 collateralState,
            uint256 pricePerTokenState,
            uint256 proposalDateState,
            Order memory orderState
        ) = optimistic.activeListings(_vault);
        proposer = proposerState;
        collateral = collateralState;
        pricePerToken = pricePerTokenState;
        proposalDate = proposalDateState;
        // Doing this because the EVM is stupid
        Order memory _order = order;
        _order.parameters = orderState.parameters;
        _order.signature = orderState.signature;
    }

    /// Sets state for proposed listing
    function _setProposalState(address _vault) internal {
        (
            address proposerState,
            uint256 collateralState,
            uint256 pricePerTokenState,
            uint256 proposalDateState,
            Order memory orderState
        ) = optimistic.proposedListings(_vault);
        proposer = proposerState;
        collateral = collateralState;
        pricePerToken = pricePerTokenState;
        proposalDate = proposalDateState;
        // Doing this because the EVM is stupid
        Order memory _order = order;
        _order.parameters = orderState.parameters;
        _order.signature = orderState.signature;
    }

    /// Proposes new listing
    function _propose(
        address _who,
        address _vault,
        uint256 _collateral,
        uint256 _price,
        OfferItem[] memory _offer
    ) internal prank(_who) {
        optimistic.propose(_vault, _collateral, _price, _offer);
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
        bytes32[] storage cancelProof
    ) internal prank(_who) {
        optimistic.rejectActive{value: _payment}(_vault, _amount, cancelProof);
        _setActiveState(_vault);
        _setOfferState(_vault);
    }

    /// Executes active listing
    function _list(
        address _who,
        address _vault,
        bytes32[] storage _validateProof
    ) internal prank(_who) {
        optimistic.list(_vault, _validateProof);
        _setActiveState(_vault);
        _setOfferState(_vault);
    }

    /// Cancels active listing
    function _cancel(
        address _who,
        address _vault,
        bytes32[] storage _delistProof
    ) internal prank(_who) {
        optimistic.cancel(_vault, _delistProof);
        _setActiveState(_vault);
        _setOfferState(_vault);
    }

    /// Fulfills seaport order
    function _fulfillOrder(address _buyer, address _vault) internal prank(_buyer) {
        (, , uint256 pricePerToken, , Order memory order) = optimistic.activeListings(_vault);
        uint256 listPrice = 0;
        for (uint256 i = 0; i < order.parameters.consideration.length; ++i) {
            listPrice += order.parameters.consideration[i].endAmount;
        }
        ISeaport(SEAPORT).fulfillOrder{value: listPrice}(order, CONDUIT_KEY);
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

    /// Setup for cashing out from sale
    function _setUpCash(uint256 _collateral, uint256 _price) internal {
        testPropose(_collateral, _price);
        _increaseTime(PROPOSAL_PERIOD);
        _list(bob, vault, validateProof);
        _increaseTime(PROPOSAL_PERIOD + 1);
        _fulfillOrder(susan, vault);
        _withdrawCollateral(bob, vault, bob);
    }

    // Setups a Seaport Offer for the items in the vault
    function _buildOffer() internal {
        offer.push(_buildERC20Offer());
        for (uint256 i; i < ERC721_SUPPLY; ++i) {
            offer.push(_buildERC721Offer(i));
        }
        for (uint256 i; i < ERC1155_SUPPLY; ++i) {
            offer.push(_buildERC1155Offer(i));
        }
    }

    function _buildERC20Offer() internal view returns (OfferItem memory) {
        return OfferItem(ItemType.ERC20, erc20, 0, ERC20_SUPPLY, ERC20_SUPPLY);
    }

    function _buildERC721Offer(uint256 id) internal view returns (OfferItem memory) {
        return OfferItem(ItemType.ERC721, erc721, id, 1, 1);
    }

    function _buildERC1155Offer(uint256 id) internal view returns (OfferItem memory) {
        return OfferItem(ItemType.ERC1155, erc1155, id, ERC1155_SUPPLY, ERC1155_SUPPLY);
    }
}
