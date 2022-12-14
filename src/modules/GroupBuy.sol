// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC165Checker} from "openzeppelin-contracts/utils/introspection/ERC165Checker.sol";
import {MerkleBase} from "../utils/MerkleBase.sol";
import {MerkleProof} from "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
import {MinPriorityQueue, Bid} from "../lib/MinPriorityQueue.sol";
import {Minter} from "../modules/Minter.sol";

import {ICryptoPunk} from "../punks/interfaces/ICryptoPunk.sol";
import {IERC721} from "../interfaces/IERC721.sol";
import {IGroupBuy, PoolInfo} from "../interfaces/IGroupBuy.sol";
import {IMarketBuyer} from "../interfaces/IMarketBuyer.sol";

/// @title GroupBuy
/// @author Tessera
/// @notice Module contract for pooling group funds to purchase and vault NFTs
/// - The bidding mechanism used here is a slightly modified implementation of the
///   Smart Batched Auction: https://github.com/FrankieIsLost/smart-batched-auction
contract GroupBuy is IGroupBuy, MerkleBase, Minter {
    /// @dev Use MinPriorityQueue library for Queue types
    using MinPriorityQueue for MinPriorityQueue.Queue;
    /// @dev Interface ID for ERC-721 tokens
    bytes4 constant _INTERFACE_ID_ERC721 = 0x80ac58cd;
    /// @notice Current pool ID
    uint256 public currentId;
    /// @notice Mapping of pool ID to vault address
    mapping(uint256 => address) public poolToVault;
    /// @notice Mapping of pool ID to PoolInfo struct
    mapping(uint256 => PoolInfo) public poolInfo;
    /// @notice Mapping of pool ID to the priority queue of valid bids
    mapping(uint256 => MinPriorityQueue.Queue) public bidPriorityQueues;
    /// @notice Mapping of pool ID to amount of Raes currently filled for the pool
    mapping(uint256 => uint256) public filledQuantities;
    /// @notice Mapping of pool ID to minimum ether price of any bid
    mapping(uint256 => uint256) public minBidPrices;
    /// @notice Mapping of pool ID to minimum reserve prices
    mapping(uint256 => uint256) public minReservePrices;
    /// @notice Mapping of pool ID to total amount of ether contributed
    mapping(uint256 => uint256) public totalContributions;
    /// @notice Mapping of pool ID to user address to total amount of ether contributed
    mapping(uint256 => mapping(address => uint256)) public userContributions;
    /// @notice Mapping of user address to pending balance available for withdrawal
    mapping(address => uint256) public pendingBalances;

    /// @dev Initializes supply contract and minimum bid price
    constructor(address _supply) Minter(_supply) {}

    /// @notice Creates a new pool
    /// @param _nftContract Address of the NFT contract
    /// @param _tokenIds List of tokenIds permitted to be purchased
    /// @param _initialPrice Initial price of the NFT(s)
    /// @param _totalSupply Total amount of Raes to be minted
    /// @param _duration Time period of pool existing before termination
    /// @param _quantity Amount of Raes being bid on
    /// @param _raePrice Ether price per Rae
    function createPool(
        address _nftContract,
        uint256[] calldata _tokenIds,
        uint256 _initialPrice,
        uint48 _totalSupply,
        uint40 _duration,
        uint256 _quantity,
        uint256 _raePrice
    ) external payable {
        // Reverts if list of tokenIds is empty
        uint256 length = _tokenIds.length;
        if (length == 0) revert InsufficientTokenIds();

        // Generates merkle root based on list size of tokenIds
        bytes32 merkleRoot = (length == 1) ? bytes32(_tokenIds[0]) : _generateRoot(_tokenIds);

        // Sets mapping of poolId to PoolInfo
        poolInfo[++currentId] = PoolInfo(
            _nftContract,
            _totalSupply,
            uint40(block.timestamp) + _duration,
            false,
            merkleRoot
        );

        // Calculates minimum bid price based on initial price of NFT and desired total supply
        minBidPrices[currentId] = _initialPrice / _totalSupply;

        // Initializes first bid in queue
        bidPriorityQueues[currentId].initialize();

        // Emits event for creating new pool
        emit Create(currentId, _nftContract, _tokenIds, msg.sender, _totalSupply, _duration);

        // Contributes ether into new pool
        contribute(currentId, _quantity, _raePrice);
    }

    /// @notice Contributes to an existing pool
    /// @param _poolId ID of the pool
    /// @param _quantity Amount of Raes being bid on
    /// @param _price Ether price per Rae
    function contribute(
        uint256 _poolId,
        uint256 _quantity,
        uint256 _price
    ) public payable {
        // Reverts if pool ID is not valid
        _verifyPool(_poolId);
        // Reverts if NFT has already been purchased OR termination period has passed
        (, uint48 totalSupply, , , ) = _verifyUnsuccessfulState(_poolId);
        // Reverts if ether contribution amount per Rae is less than minimum bid price per Rae
        if (msg.value < _quantity * minBidPrices[_poolId] || _quantity == 0)
            revert InvalidContribution();
        // Reverts if ether payment amount is not equal to total amount being contributed
        if (msg.value != _quantity * _price) revert InvalidPayment();

        // Updates user and pool contribution amounts
        userContributions[_poolId][msg.sender] += msg.value;
        totalContributions[_poolId] += msg.value;

        // Calculates remaining supply based on total possible supply and current filled quantity amount
        uint256 remainingSupply = totalSupply - filledQuantities[_poolId];
        // Calculates quantity amount being filled at any price
        uint256 fillAtAnyPriceQuantity = remainingSupply < _quantity ? remainingSupply : _quantity;

        // Checks if quantity amount being filled is greater than 0
        if (fillAtAnyPriceQuantity > 0) {
            // Inserts bid into end of queue
            bidPriorityQueues[_poolId].insert(msg.sender, _price, fillAtAnyPriceQuantity);
            // Increments total amount of filled quantities
            filledQuantities[_poolId] += fillAtAnyPriceQuantity;
        }

        // Calculates unfilled quantity amount based on desired quantity and actual filled quantity amount
        uint256 unfilledQuantity = _quantity - fillAtAnyPriceQuantity;
        // Processes bids in queue to recalculate unfilled quantity amount
        unfilledQuantity = processBidsInQueue(_poolId, unfilledQuantity, _price);

        // Recalculates filled quantity amount based on updated unfilled quantity amount
        uint256 filledQuantity = _quantity - unfilledQuantity;
        // Updates minimum reserve price if filled quantity amount is greater than 0
        if (filledQuantity > 0) minReservePrices[_poolId] = getMinPrice(_poolId);

        // Emits event for contributing ether to pool based on desired quantity amount and price per Rae
        emit Contribute(
            _poolId,
            msg.sender,
            msg.value,
            _quantity,
            _price,
            minReservePrices[_poolId]
        );
    }

    /// @notice Purchases NFT once contribution amount has been met
    /// @param _poolId ID of the pool
    /// @param _market Address of the market buyer contract
    /// @param _nftContract Address of the NFT contract
    /// @param _tokenId ID of the token
    /// @param _price Total ether price of the listed NFT
    /// @param _purchaseOrder Bytes data of the purchase order parameters
    /// @param _purchaseProof Merkle proof of the tokenId in the list of permitted tokenIds
    function purchase(
        uint256 _poolId,
        address _market,
        address _nftContract,
        uint256 _tokenId,
        uint256 _price,
        bytes memory _purchaseOrder,
        bytes32[] memory _purchaseProof
    ) external {
        // Reverts if pool ID is not valid
        _verifyPool(_poolId);
        // Reverts if NFT has already been purchased OR termination period has passed
        (
            address nftContract,
            uint48 totalSupply,
            ,
            ,
            bytes32 merkleRoot
        ) = _verifyUnsuccessfulState(_poolId);
        // Reverts if NFT contract is not equalt to NFT contract set on pool creation
        if (_nftContract != nftContract) revert InvalidContract();
        // Reverts if price is greater than total contribution amount of pool
        if (_price > minReservePrices[_poolId] * filledQuantities[_poolId])
            revert InvalidPurchase();

        // Checks merkle proof based on size of array
        if (_purchaseProof.length == 0) {
            // Hashes tokenId to verify merkle root if proof is empty
            if (bytes32(_tokenId) != merkleRoot) revert InvalidProof();
        } else {
            // Verifies merkle proof based on position of leaf node in tree
            bytes32 leaf = keccak256(abi.encode(_tokenId));
            if (!MerkleProof.verify(_purchaseProof, merkleRoot, leaf)) revert InvalidProof();
        }

        // Decrements actual price from total pool contributions
        totalContributions[_poolId] -= _price;

        // Encodes NFT contract and tokenId into purchase order
        bytes memory nftData = abi.encode(_nftContract, _tokenId);
        // Encodes arbitrary amount of data based on market buyer to execute purchase
        _purchaseOrder = abi.encodePacked(nftData, _purchaseOrder);

        // Executes purchase order transaction through market buyer contract and deploys new vault
        address vault = IMarketBuyer(_market).execute{value: _price}(_purchaseOrder);

        // Checks if NFT contract supports ERC165 and interface ID of ERC721 tokens
        if (ERC165Checker.supportsInterface(_nftContract, _INTERFACE_ID_ERC721)) {
            // Verifes vault is owner of ERC-721 token
            if (IERC721(_nftContract).ownerOf(_tokenId) != vault) revert UnsuccessfulPurchase();
        } else {
            // Verifies vault is owner of CryptoPunk token
            if (ICryptoPunk(_nftContract).punkIndexToAddress(_tokenId) != vault)
                revert UnsuccessfulPurchase();
        }

        // Stores mapping value of poolId to newly deployed vault
        poolToVault[_poolId] = vault;
        // Sets pool state to successful
        poolInfo[_poolId].success = true;

        // Emits event for purchasing NFT at given price
        emit Purchase(_poolId, vault, _nftContract, _tokenId, _price);
    }

    /// @notice Mints Raes based on contribution amount and refunds remaining ether
    /// @param _poolId ID of the pool
    /// @param _mintProof Merkle proof for executing minting of Rae tokens
    function claim(uint256 _poolId, bytes32[] calldata _mintProof) external {
        // Reverts if pool ID is not valid
        _verifyPool(_poolId);
        // Reverts if purchase has not been made AND termination period has not passed
        (, , , bool success, ) = _verifySuccessfulState(_poolId);
        // Reverts if contribution balance of user is insufficient
        uint256 contribution = userContributions[_poolId][msg.sender];
        if (contribution == 0) revert InsufficientBalance();

        // Deletes user contribution from storage
        delete userContributions[_poolId][msg.sender];

        // Set up scoped values for iteration
        uint256 totalQty;
        uint256 reservePrice = minReservePrices[_poolId];
        uint256[] memory bidIds = getOwnerToBidIds(_poolId, msg.sender);
        uint256 length = bidIds.length;

        // Iterates through all active bidIds of the caller
        if (success) {
            for (uint256 i; i < length; ++i) {
                // Gets bid quantity from storage
                Bid storage bid = bidPriorityQueues[_poolId].bidIdToBidMap[bidIds[i]];
                uint256 quantity = bid.quantity;
                // Resets bid quantity amount
                bid.quantity = 0;
                // Increments total quantity of Raes to be minted
                totalQty += quantity;
                // Decrements quantity price from total user contribution balance
                contribution -= quantity * reservePrice;
            }

            // Mints total quantity of Raes to caller
            _mintRaes(poolToVault[_poolId], msg.sender, totalQty, _mintProof);
        }

        // Transfers remaining contribution balance back to caller
        payable(msg.sender).call{value: contribution}("");

        // Withdraws pending balance of caller if available
        if (pendingBalances[msg.sender] > 0) withdrawBalance();

        // Emits event for claiming tokens and receiving ether refund
        emit Claim(_poolId, msg.sender, totalQty, contribution);
    }

    function withdrawBalance() public {
        // Reverts if caller balance is insufficient
        uint256 balance = pendingBalances[msg.sender];
        if (balance == 0) revert InsufficientBalance();

        // Resets pending balance amount
        delete pendingBalances[msg.sender];

        // Transfers pending ether balance to caller
        payable(msg.sender).call{value: balance}("");
    }

    /// @notice Attempts to accept bid for specifc quantity and price
    /// @param _poolId ID of the pool
    /// @param _quantity Amount of Raes being filled
    /// @param _price Price of ether per Rae token
    /// @return quantity Unfilled quantity amount
    function processBidsInQueue(
        uint256 _poolId,
        uint256 _quantity,
        uint256 _price
    ) private returns (uint256 quantity) {
        quantity = _quantity;
        while (quantity > 0) {
            // Retrieves lowest bid in queue
            Bid storage lowestBid = bidPriorityQueues[_poolId].getMin();
            // Breaks out of while loop if given price is less than than lowest bid price
            if (_price < lowestBid.price) {
                break;
            }

            uint256 lowestBidQuantity = lowestBid.quantity;
            // Checks if lowest bid quantity amount is greater than given quantity amount
            if (lowestBidQuantity > quantity) {
                // Decrements given quantity amount from lowest bid quantity
                lowestBid.quantity -= quantity;
                // Calculates partial contribution of bid by quantity amount and price
                uint256 contribution = quantity * lowestBid.price;

                // Decrements partial contribution amount of lowest bid from total and user contributions
                totalContributions[_poolId] -= contribution;
                userContributions[_poolId][lowestBid.owner] -= contribution;
                // Increments pending balance of lowest bid owner
                pendingBalances[lowestBid.owner] += contribution;

                // Inserts new bid with given quantity amount into proper position of queue
                bidPriorityQueues[_poolId].insert(msg.sender, _price, quantity);
                // Resets quantity amount to exit while loop
                quantity = 0;
            } else {
                // Calculates total contribution of bid by quantity amount and price
                uint256 contribution = lowestBid.quantity * lowestBid.price;

                // Decrements full contribution amount of lowest bid from total and user contributions
                totalContributions[_poolId] -= contribution;
                userContributions[_poolId][lowestBid.owner] -= contribution;
                // Increments pending balance of lowest bid owner
                pendingBalances[lowestBid.owner] += contribution;

                // Removes lowest bid in queue
                bidPriorityQueues[_poolId].delMin();
                // Inserts new bid with lowest bid quantity amount into proper position of queue
                bidPriorityQueues[_poolId].insert(msg.sender, _price, lowestBidQuantity);
                // Decrements lowest bid quantity from total quantity amount
                quantity -= lowestBidQuantity;
            }
        }
    }

    /// @notice Gets bid values in queue of given pool
    /// @param _poolId ID of the pool
    /// @param _bidId ID of the bid in queue
    function getBidInQueue(uint256 _poolId, uint256 _bidId)
        public
        view
        returns (
            uint256 bidId,
            address owner,
            uint256 price,
            uint256 quantity
        )
    {
        Bid storage bid = bidPriorityQueues[_poolId].bidIdToBidMap[_bidId];
        bidId = bid.bidId;
        owner = bid.owner;
        price = bid.price;
        quantity = bid.quantity;
    }

    /// @notice Gets minimum bid price of queue for given pool
    /// @param _poolId ID of the pool
    function getMinPrice(uint256 _poolId) public view returns (uint256) {
        return bidPriorityQueues[_poolId].getMin().price;
    }

    /// @notice Gets next bidId in queue of given pool
    /// @param _poolId ID of the pool
    function getNextBidId(uint256 _poolId) public view returns (uint256) {
        return bidPriorityQueues[_poolId].nextBidId;
    }

    /// @notice Gets total number of bids in queue for given pool
    /// @param _poolId ID of the pool
    function getNumBids(uint256 _poolId) public view returns (uint256) {
        return bidPriorityQueues[_poolId].numBids;
    }

    /// @notice Gets quantity of Raes for bid of given pool
    /// @param _poolId ID of the pool
    /// @param _bidId ID of the bid in queue
    function getBidQuantity(uint256 _poolId, uint256 _bidId) public view returns (uint256) {
        return bidPriorityQueues[_poolId].bidIdToBidMap[_bidId].quantity;
    }

    /// @notice Gets list of bidIds for address of given pool
    /// @param _poolId ID of the pool
    /// @param _owner Address of the owner
    function getOwnerToBidIds(uint256 _poolId, address _owner)
        public
        view
        returns (uint256[] memory)
    {
        return bidPriorityQueues[_poolId].ownerToBidIds[_owner];
    }

    /// @notice Logs entire queue of given pool
    /// @dev Must include console log to debug
    /// @param _poolId ID of the pool
    function printQueue(uint256 _poolId) public view {
        uint256 counter;
        uint256 index = 1;
        MinPriorityQueue.Queue storage queue = bidPriorityQueues[_poolId];
        uint256 numBids = queue.numBids;
        while (counter < numBids) {
            Bid memory bid = queue.bidIdToBidMap[index];
            if (bid.bidId == 0) {
                ++index;
                continue;
            }
            ++index;
            ++counter;
        }
    }

    /// @dev Generates merkle root for list of tokenIds
    function _generateRoot(uint256[] calldata _tokenIds)
        internal
        pure
        returns (bytes32 merkleRoot)
    {
        // Creates empty leaf nodes array based on size of tokenIds
        uint256 length = _tokenIds.length;
        bytes32[] memory leaves = new bytes32[](length);
        unchecked {
            for (uint256 i; i < length; ++i) {
                // Hashes each tokenId into leaf node and set at index position of array
                leaves[i] = keccak256(abi.encode(_tokenIds[i]));
            }
        }
        // Generates merkle root from given leaf nodes
        merkleRoot = getRoot(leaves);
    }

    /// @dev Reverts if pool ID is not valid
    function _verifyPool(uint256 _poolId) internal view {
        if (_poolId == 0 || _poolId > currentId) revert InvalidPool();
    }

    // Reverts if NFT has already been purchased OR termination period has passed
    function _verifyUnsuccessfulState(uint256 _poolId)
        internal
        view
        returns (
            address,
            uint48,
            uint40,
            bool,
            bytes32
        )
    {
        PoolInfo memory pool = poolInfo[_poolId];
        if (pool.success || block.timestamp > pool.terminationPeriod) revert InvalidState();
        return (
            pool.nftContract,
            pool.totalSupply,
            pool.terminationPeriod,
            pool.success,
            pool.merkleRoot
        );
    }

    // Reverts if NFT has not been purchased AND termination period has not passed
    function _verifySuccessfulState(uint256 _poolId)
        internal
        view
        returns (
            address,
            uint48,
            uint40,
            bool,
            bytes32
        )
    {
        PoolInfo memory pool = poolInfo[_poolId];
        if (!pool.success && block.timestamp < pool.terminationPeriod) revert InvalidState();
        return (
            pool.nftContract,
            pool.totalSupply,
            pool.terminationPeriod,
            pool.success,
            pool.merkleRoot
        );
    }
}
