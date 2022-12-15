# Tessera - Versus contest details
- Total Prize Pool: $32,070 USDC
  - HM awards: $16,500 USDC
  - QA report awards: $2,000 USDC
  - Gas report awards: $1,500 USDC
  - Judge + presort awards: $2,870 USDC
  - Scout awards: $500 USDC
  - Mitigation review contest: $8,700 USDC
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2022-12-tessera-versus-contest/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts December 16, 2022 20:00 UTC
- Ends December 19, 2022 20:00 UTC

## C4udit / Publicly Known Issues

The C4audit output for the contest can be found [here](add link to report) within an hour of contest opening.

*Note for C4 wardens: Anything included in the C4udit output is considered a publicly known issue and is ineligible for awards.*

# Overview

[![Gitbook](https://img.shields.io/badge/docs-%F0%9F%93%84-blue)](https://docs.tessera.co)

Tessera is a decentralized protocol that allows for shared ownership and governance of NFTs. When an NFT is vaulted, the newly minted tokens function as normal ERC-1155 tokens which govern the non-custodial Vault containing the NFT(s).

The Tessera Protocol is designed around the concept of [Hyperstructures](https://jacob.energy/hyperstructures.html), which are _crypto protocols that can run for free and forever, without maintenance, interruption or intermediaries_.

### Vaults

> The home of all items on Tessera

Vaults are a slightly modified implementation of [PRBProxy](https://github.com/paulrberg/prb-proxy) which is a basic and non-upgradeable proxy contract. Think of a Vault as a smart wallet that enables the execution of arbitrary smart contract calls in a single transaction. Generally, the calls a Vault can make are disabled and must be explicitly allowed through permissions. The vault is intentionally left unopinionated and extremely flexible for experimentation in the future.

### Permissions

> Authorize transactions performed on a vault

A permission is a combination of a _Module_ contract, _Target_ contract, and specific function _Selector_ in a target contract that can be executed by the vault. A group of permissions creates the set of functions that are callable by the Vault in order to carry out its specific use case. Each permission is then hashed and used as a leaf node to generate a merkle tree, where the merkle root of the tree is stored on the vault itself. Whenever a transaction is executed on a vault, a merkle proof is used to verify legitimacy of the leaf node (Permission) and the merkle root.

### Modules

> Make vaults do cool stuff

Modules are the bread and butter of what makes Tessera unique. At Vault creation, modules are added to permissions for the vault. Each module should have specific goals it plans to accomplish. Some general examples are Buyouts, Inflation, and Renting. If a vault wants to update the set of modules enabled, then it must have the migration module enabled and go through the migration process.
In general, it is highly recommended for vaults to have a module that enables items to be removed from vaults. Without this, all items inside of a vault will be stuck forever.

### Targets

> Execute vault transactions

Targets are stateless script-like contracts for executing transactions by the Vault on-behalf of a user. Only functions of a target contract that are initially set as enabled permissions for a vault can be executed by a vault.

## How Does Optimistic Listings Work?

### Step 1: Create Listing Proposal

Unlike Optimistic Buyouts, Optimist Listings do not use ETH (except for gas) in proposals. A user must be a current Rae holder in order to propose a listing. They must select what marketplace the listing will be done on, what price the NFT(s) should be listed for, how long the listing should last (if applicable), and how many Raes they are willing to use to sponsor the listing.

If there is a current listing in the review period, another use can list lower which would restart the review period at the same price. There can only be one active listing for a vault at a time, even if its partial.

A proposal will include all NFTs within the vault.

### Step 2: Listing Review Period - Reject Window

After a user creates a listing proposal, there will be a 4 day rejection window. All vault holders will be able to reject a proposal by purchasing Raes within the proposal pool. These Raes will be priced according to the price inputed in step 1. Immediately when all the Raes within the proposal period are purchased, the proposal will end.

If at the end of the review period there are any Raes remaining within the pool, the NFT(s) will then be listed on the marketplace for the proposed time/price.

### Step 3: Active Listing Period

Once the NFT(s) are listed on a marketplace, anybody can purchase the NFT normally. The Raes that were contributed to the pool during the review period are then stored away.

**Delisting**

Users that initiated the proposal can claim the Raes from the lock up at any time for free (besides gas).

If other users want to cancel the listing, they can purchase the Raes for the implied valuation, similar to the review period.

If there are no more Raes left in the sponsor storage, the NFT will be immediately delisted from the marketplace.

**Another Listing Proposal**

There can only be one active listing per marketplace. To prevent a user from holding a vault hostage and never letting the piece be reasonably bought, cheaper counter-listings can be created.

If a user wants to make a listing at a lower price at the same valuation, they can go through steps 1 and 2. The proposed listing price must be at least 5% cheaper than the active proposal price.

If there are still Raes remaining in the new optimistic listing by the end of the new proposals listing period, the old listing is immediately terminated. The Raes from the old listing will be returned to the proposal creator, and the NFT(s) will then be listed for cheaper.

**Listing Expiration**

Listings can never expire, they can only be canceled via Optimistic Listings.

### Step 4: Listing is Purchased

Once the listing is purchased, the vault will act similarly to an Optimistic Buyout. The proposer will have their Raes returned to them, and all users can burn their Raes for their portion of ETH gained from the sale.


## How does Group Buying Work?

### Step 1:  Create Group Buy Pool

A user will first create a Group Buy Pool, by selecting what NFT collection they would like to start the pool for. Users will only be able to select NFT collections that are currently supported on Tessera with Protoforms (front end only).

The user will then specify which token IDs are valid to be purchased (which specific NFTs). They will also select the total supply of Raes, and the initial price that they think the NFT will sell for. This initial price will then determine the minimum bid price anyone can make for the pool. The final step will be for the creator to contribute to the pool (at least the minimum price).

### Step 2: Users Deposit Funds to Pool

To contribute to the pool, the user will specify how many tokens they want, and the price they want to pay per token (has to be greater than minimum price). The total amount that they will pay is price per Rae * amount of tokens.

### Step 3: Other Users Deposit Funds to Pool (Filtering)

If the quantity of Raes has been filled (filled quantities = total supply) then users contributing to the pool must at least meet the current minimum reserve price per Rae to have their bid included.

As other users deposit funds into the pool, the pool will begin to increase. Once the total supply of Raes have been sold (filled quantities = total supply), the pool will start filtering. During the filtering process, the pool will start to remove the quantity of Raes from lower bids in order to fill the orders with a higher price per-Rae.

If two users place bids at the same price but with different quantities, the queue will pull from the bid with a higher quantity first. If the users have the same quantity as well, the bid that was placed later will have Raes removed.

If a users bid becomes less than the current minimum reserve price, the user’s bid will not be included in the pool. They will be able to withdrawal their refund at any time.

Users cannot withdraw funds from a pool unless their bid gets removed from the pool.

### Step 4: A User Executes Purchase Call

Once the pool has raised enough ETH to purchase a specified NFT that is listed on a marketplace, any user is able to execute the purchase order once the minBid * # Raes is enough to successfully purchase an NFT Id from the initial list used to create the pool.  (arbitrary amount of data that is based on the marketplace the NFT is listed on) on behalf of the pool.

Once the purchase is executed, a new vault gets deployed with the proper permissions, the NFT then gets transferred to the vault, and ownership of the NFT by the vault is verified.

### Step 5: Users Claim Raes

After the purchase is made, users can then claim their portion of the Raes (based on amount contributed).

If there is excess ETH in the pool after the purchase is made, when users claim their Raes they also will receive a refund for their portion of excess ETH.

### Files in scope
| Contract | SLOC | Purpose | Libraries used |  
| ----------- | ----------- | ----------- | ----------- |
| src/seaport/modules/OptimisticListingSeaport.sol | 318 | Module contract for listing vault assets through the Seaport protocol | [Seaport](https://github.com/ProjectOpenSea/seaport) |
| src/seaport/targets/SeaportLister.sol | 35 | Target contract for listing orders on Seaport | [Seaport](https://github.com/ProjectOpenSea/seaport) |
| src/modules/GroupBuy.sol | 290 | Module contract for pooling group funds to purchase and vault NFTs | [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts) |
| src/lib/MinPriorityQueue.sol | 103 | Queue used for smart batch auction in GroupBuy | []() |
| src/punks/protoforms/PunksMarketBuyer.sol | 49 | Protoform contract for executing CryptoPunk purchase orders and deploying vaults | []() |

### All other source contracts (not in scope)
| Contract |
| ----------- |
| src/constants/Memory.sol |
| src/constants/Permit.sol |
| src/constants/Supply.sol |
| src/constants/Transfer.sol |
| src/interfaces/IBaseVault.sol |
| src/interfaces/IERC20.sol |
| src/interfaces/IERC721.sol |
| src/interfaces/IERC1155.sol |
| src/interfaces/IGroupBuy.sol |
| src/interfaces/IIssuerFactory.sol |
| src/interfaces/IMarketBuyer.sol |
| src/interfaces/IMetadataDelegate.sol |
| src/interfaces/IMinter.sol |
| src/interfaces/IModule.sol |
| src/interfaces/INFTReceiver.sol |
| src/interfaces/IProtofrom.sol |
| src/interfaces/IRae.sol |
| src/interfaces/ISupply.sol |
| src/interfaces/ITransfer.sol |
| src/interfaces/IVault.sol |
| src/interfaces/IVaultFactory.sol |
| src/interfaces/IVaultRegistry.sol |
| src/mocks/MockERC20.sol |
| src/mocks/MockERC721.sol |
| src/mocks/MockERC1155.sol |
| src/mocks/MockEthReceiver.sol |
| src/mocks/MockModule.sol |
| src/mocks/MockPermitter.sol |
| src/mocks/MockSender.sol |
| src/modules/Minter.sol |
| src/modules/Module.sol |
| src/protoforms/BaseVault.sol |
| src/protoforms/IssuerFactory.sol |
| src/protoforms/Protoform.sol |
| src/punks/interfaces/ICryptoPunk.sol |
| src/punks/interfaces/IOptimisticListing.sol |
| src/punks/interfaces/IPunksMarketAdapter.sol |
| src/punks/interfaces/IMunksMarketBuyer.sol |
| src/punks/interfaces/IPunksMarketLister.sol |
| src/punks/interfaces/IPunksProtofrom.sol |
| src/punks/interfaces/IWrappedPunks.sol |
| src/punks/modules/OptimisticListingPunks.sol |
| src/punks/protoforms/PunksProtoform.sol |
| src/punks/targets/PunksMarketLister.sol |
| src/punks/utils/CryptoPunksMarket.sol |
| src/punks/utils/PunksMarketAdapter.sol |
| src/punks/utils/WrappedPunk.sol |
| src/references/SupplyReference.sol |
| src/references/TransferReference.sol |
| src/seaport/interfaces/IOptimisticListingSeaport.sol |
| src/seaport/interfaces/ISeaportLister.sol |
| src/targets/Supply.sol |
| src/targets/Transfer.sol |
| src/utils/MerkleBase.sol |
| src/utils/MetadataDelegate.sol |
| src/utils/Multicall.sol |
| src/utils/NFTReceiver.sol |
| src/utils/PermitBase.sol |
| src/utils/SafeSend.sol |
| src/utils/SelfPermit.sol |
| src/Rae.sol |
| src/Vault.sol |
| src/VaultFactory.sol |
| src/VaultRegistry.sol |

## Tests

> Required **> node 12**

> On windows use WSL or the Docker image
#### Install Foundry on Mac/Unix:

```bash
curl -L https://foundry.paradigm.xyz | bash
```

#### Install Foundry with Docker:

```
docker pull ghcr.io/foundry-rs/foundry:latest
```

#### Environment variables:

GOERLI_RPC_URL is Required
ETHERSCAN_API_KEY and PRIVATE_KEY are only required if you want to run the foundry script
```
GOERLI_RPC_URL=
ETHERSCAN_API_KEY=
PRIVATE_KEY=
```

Or copy .env.example to .env which has a public RPC

#### Install node packages:

```
npm ci
```

#### Install gitmodule dependencies:

```
git submodule update --init --recursive
```

#### Compile contracts:

```
forge build
```

#### Run tests:

```
make test-nofork
make test-fork
```

#### Run gas report:

```
forge test --gas-report
```

#### Run linter:

```
npm run lint
```
