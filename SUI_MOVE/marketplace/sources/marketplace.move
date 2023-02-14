module nfts::marketplace {
    use sui::dynamic_object_field as ofield;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use std::vector as vec;

    /// For when amount paid does not match the expected.
    const EAmountIncorrect: u64 = 0;
    /// For when someone tries to delist without ownership.
    const ENotOwner: u64 = 1;
    const EItemNotFound: u64 = 2;
    const EOwnerExist: u64 = 3;
    const EItemExist: u64 = 4;

    struct Marketplace<phantom COIN> has key {
        id: UID,
        owner_list: vector<address>
    }

    struct Listing<T: key + store> has key, store {
        id: UID,
        ask: u64,
        item: T,
        owner: address,
    }

    struct NFTOwnerBelaunch has key, store {
        id: UID,
        item_ids: vector<ID>
    }

    struct MarketOwnerCap has key, store { id: UID }

    // ======= Publishing =======
    fun init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let id = object::new(ctx);

        transfer::transfer(
            MarketOwnerCap {
                id
            },
            sender
        )
    }

    /// Create a new shared Marketplace.
    public entry fun create<COIN>(_admin: & MarketOwnerCap, ctx: &mut TxContext) {
        let marketplace = Marketplace<COIN> { 
            id: object::new(ctx),
            owner_list: vec::empty<address>()
        };

        transfer::share_object(marketplace);
    }

    // Listing an NFT on Marketplace
    public entry fun mint_nfts_owner<COIN>(
        marketplace: &mut Marketplace<COIN>,
        ctx: &mut TxContext
    ) {
        let owner_addr = tx_context::sender(ctx);
        assert!(!vec::contains(&marketplace.owner_list, &owner_addr), EOwnerExist);

        let owner_id = object::new(ctx);
        let nft_owner_cap = NFTOwnerBelaunch {
            id: owner_id,
            item_ids: vec::empty<ID>()
        };

        transfer::transfer(
            nft_owner_cap,
            owner_addr
        );

        vec::push_back(&mut marketplace.owner_list, owner_addr);
    }

    public entry fun list<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        owner: &mut NFTOwnerBelaunch,
        item: T,
        ask: u64,
        ctx: &mut TxContext
    ) {
        let item_id = object::id(&item);

        let listing = Listing<T> {
            ask,
            item: item,
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
        };

        ofield::add(&mut marketplace.id, item_id, listing);

        if (!vec::contains(&owner.item_ids, &item_id)) {
            vec::push_back(&mut owner.item_ids, item_id);
        }
    }

    public entry fun delist<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        owner_info: &mut NFTOwnerBelaunch,
        item_id: ID,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        let Listing<T> {
            id,
            item,
            owner,
            ask: _,
        } = ofield::remove(&mut marketplace.id, item_id);

        assert!(sender == owner, ENotOwner);
        
        let (_, index) = vec::index_of<ID>(&owner_info.item_ids, &item_id);
        vec::remove(&mut owner_info.item_ids, index);
        transfer::transfer(item, sender);

        object::delete(id);
    }

    // public entry fun delist_and_take<T: key + store, COIN>(
    //     marketplace: &mut Marketplace<COIN>,
    //     owner: &mut NFTOwnerBelaunch,
    //     item_id: ID,
    //     ctx: &mut TxContext
    // ) {
    //     let item = delist<T, COIN>(marketplace, owner, item_id, ctx);
    //     transfer::transfer(item, tx_context::sender(ctx));
    // }

    public entry fun buy<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        item_id: ID,
        paid: Coin<COIN>,
        ctx: &mut TxContext,
    ) {
        let buyer = tx_context::sender(ctx);

        let Listing<T> {
            id,
            ask,
            item,
            owner
        } = ofield::remove(&mut marketplace.id, item_id);

        assert!(coin::value(&paid) >= ask, EAmountIncorrect);
        
        transfer::transfer(
            coin::split(&mut paid, ask, ctx),
            owner
        );
        transfer::transfer(
            paid,
            buyer
        );
        transfer::transfer(item, buyer);

        object::delete(id);
    }

    // public entry fun buy_and_take<T: key + store, COIN>(
    //     marketplace: &mut Marketplace<COIN>,
    //     item_id: ID,
    //     paid: Coin<COIN>,
    //     ctx: &mut TxContext
    // ) {
    //     transfer::transfer(
    //         buy<T, COIN>(marketplace, item_id, paid, ctx),
    //         tx_context::sender(ctx)
    //     )
    // }
}