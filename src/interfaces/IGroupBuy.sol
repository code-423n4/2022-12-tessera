// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {MinPriorityQueue} from "../lib/MinPriorityQueue.sol";

struct PoolInfo {
    address nftContract;
    uint48 totalSupply;
    uint40 terminationPeriod;
    bool success;
    bytes32 merkleRoot;
}

/// @dev Interface for GroupBuy protoform contract
interface IGroupBuy {
    error InsufficientBalance();
    error InsufficientTokenIds();
    error InvalidContract();
    error InvalidContribution();
    error InvalidPayment();
    error InvalidPool();
    error InvalidProof();
    error InvalidPurchase();
    error InvalidState();
    error NotOwner();
    error UnsuccessfulPurchase();

    event Create(
        uint256 indexed _poolId,
        address indexed _nftContract,
        uint256[] indexed _tokenIds,
        address _creator,
        uint48 _totalSupply,
        uint40 _duration
    );

    event Contribute(
        uint256 indexed _poolId,
        address indexed _contributor,
        uint256 _ethContribution,
        uint256 _quantity,
        uint256 _price,
        uint256 _minReservePrice
    );

    event Purchase(
        uint256 indexed _poolId,
        address indexed _vault,
        address indexed _nftContract,
        uint256 _tokenId,
        uint256 _price
    );

    event Claim(
        uint256 indexed _poolId,
        address indexed _claimer,
        uint256 _raeAmount,
        uint256 _ethRefund
    );

    function claim(uint256 _poolId, bytes32[] calldata _mintProof) external;

    function contribute(
        uint256 _poolId,
        uint256 _quantity,
        uint256 _price
    ) external payable;

    function createPool(
        address _nftContract,
        uint256[] calldata _tokenIds,
        uint256 _initialPrice,
        uint48 _totalSupply,
        uint40 _duration,
        uint256 _quantity,
        uint256 _raePrice
    ) external payable;

    function currentId() external view returns (uint256);

    function filledQuantities(uint256) external view returns (uint256);

    function minBidPrices(uint256) external view returns (uint256);

    function minReservePrices(uint256) external view returns (uint256);

    function pendingBalances(address) external view returns (uint256);

    function poolInfo(uint256)
        external
        view
        returns (
            address nftContract,
            uint48 totalSupply,
            uint40 terminationPeriod,
            bool success,
            bytes32 merkleRoot
        );

    function poolToVault(uint256) external view returns (address);

    function purchase(
        uint256 _poolId,
        address _market,
        address _nftContract,
        uint256 _tokenId,
        uint256 _price,
        bytes memory _purchaseOrder,
        bytes32[] memory _purchaseProof
    ) external;

    function totalContributions(uint256) external view returns (uint256);

    function userContributions(uint256, address) external view returns (uint256);
}
