// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import {BaseVault} from "../src/protoforms/BaseVault.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {OptimisticListingSeaport} from "../src/seaport/modules/OptimisticListingSeaport.sol";
import {SeaportLister} from "../src/seaport/targets/SeaportLister.sol";
import {Supply} from "../src/targets/Supply.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {VaultRegistry} from "../src/VaultRegistry.sol";
import {WETH} from "@rari-capital/solmate/src/tokens/WETH.sol";

import {ConduitControllerInterface} from "seaport/interfaces/ConduitControllerInterface.sol";
import {IERC1155} from "../src/interfaces/IERC1155.sol";
import {InitInfo} from "../src/interfaces/IVault.sol";
import {IRae} from "../src/interfaces/IRae.sol";
import {ISupply} from "../src/interfaces/ISupply.sol";
import {ItemType, OfferItem} from "seaport/lib/ConsiderationStructs.sol";

contract SeaportDeploy is Script {
    BaseVault baseVault;
    MockERC721 erc721;
    OptimisticListingSeaport optimisticModule;
    SeaportLister listerTarget;
    Supply supplyTarget;
    VaultRegistry registry;
    WETH weth;

    address rae;
    address vault;
    address conduit;
    address[] modules;
    bytes32[] merkleTree;
    bytes32[] mintProof;
    bytes32[] burnProof;
    bytes32[] validateProof;
    bytes32[] cancelProof;

    address constant SEAPORT = 0x00000000006c3852cbEf3e08E8dF289169EdE581;
    address constant ZONE = address(0);
    address constant CONTROLLER = 0x00000000F9490004C11Cef243f5400493c00Ad63;
    bytes32 constant CONDUIT_KEY = 0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000;
    address constant OPENSEA_RECIPIENT = address(0);

    uint256 constant PROPOSAL_PERIOD = 0;
    uint256 constant TOTAL_SUPPLY = 100;

    uint256 tokenId = 1;
    uint256 collateral = TOTAL_SUPPLY / 2;
    uint256 pricePerToken = .0001 ether;
    uint256 listingPrice = TOTAL_SUPPLY * pricePerToken;

    function run() public {
        vm.startBroadcast();
        weth = new WETH();
        registry = new VaultRegistry();
        supplyTarget = new Supply(address(registry));
        (conduit, ) = ConduitControllerInterface(CONTROLLER).getConduit(CONDUIT_KEY);
        listerTarget = new SeaportLister(conduit);
        optimisticModule = new OptimisticListingSeaport(
            address(registry),
            SEAPORT,
            ZONE,
            CONDUIT_KEY,
            address(supplyTarget),
            address(listerTarget),
            payable(msg.sender),
            payable(OPENSEA_RECIPIENT),
            PROPOSAL_PERIOD,
            payable(address(weth))
        );
        baseVault = new BaseVault(address(registry));
        erc721 = new MockERC721();

        rae = registry.rae();
        IRae(rae).transferController(msg.sender);

        vault = deployVault();
        erc721.mint(vault, tokenId);

        propose();
        list();

        vm.stopBroadcast();
    }

    function deployVault() public returns (address vault) {
        modules = new address[](1);
        modules[0] = address(optimisticModule);
        merkleTree = baseVault.generateMerkleTree(modules);
        burnProof = baseVault.getProof(merkleTree, 0);
        validateProof = baseVault.getProof(merkleTree, 1);
        cancelProof = baseVault.getProof(merkleTree, 2);

        InitInfo[] memory calls = new InitInfo[](1);
        calls[0] = InitInfo({
            target: address(supplyTarget),
            data: abi.encodeCall(ISupply.mint, (msg.sender, TOTAL_SUPPLY)),
            proof: mintProof
        });

        vault = baseVault.deployVault(modules, calls);
        console.log("VAULT:", vault);
    }

    function propose() public {
        OfferItem[] memory offers = new OfferItem[](1);
        OfferItem memory item = OfferItem(ItemType.ERC721, address(erc721), tokenId, listingPrice, listingPrice);
        offers[0] = item;

        IERC1155(rae).setApprovalForAll(address(optimisticModule), true);
        optimisticModule.propose(vault, collateral, pricePerToken, offers);
    }

    function list() public {
        optimisticModule.list(vault, validateProof);
    }

    function cancel() public {
        optimisticModule.cancel(vault, cancelProof);
    }
}
