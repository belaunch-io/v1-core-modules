module nfts::store {
    use sui::url::{Self, Url};
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{sender, TxContext};
    use std::string::{Self, String};
    use sui::sui::SUI;
    use std::option::{Self, Option};
    use sui::dynamic_object_field as dof;
    use sui::coin::{Self, Coin};
    use sui::transfer::{transfer, share_object};
    use std::vector as vec;
    use sui::event::emit;
    use sui::balance::{Self, Balance};

    const EAmountIncorrect: u64 = 0;
    const EPurchasedItem: u64 = 1;
    const ENotOwner: u64 = 2;
    const EOwnerExist: u64 = 3;
    const EWrongTime: u64 = 4;

    // ======= Types =======
    struct Stores has key, store {
        id: UID,
        owner_list: vector<address>
    }

    struct StoreOwnerCap has key { 
        id: UID,
        store_id: ID
    }

    struct ItemStore has key, store {
        id: UID,
        revenue: u64,
        total_amount: u64,
        name: String,
        logo_url: Url,
        banner_url: Url,
        description: vector<u8>,
        start_time: u64,
        owner: address,
        paid: Balance<SUI>,
        item_ids: vector<ID>
    }

    struct Item has key, store {
        id: UID,
        name: String,
        description: String,
        url: Url,
    }

    struct ListedItem has key, store {
        id: UID,
        url: Url,
        name: String,
        description: String,
        price: u64,
        quantity: Option<u64>,
        buyers: vector<address>
    }

    // ======= Events =======
    struct ItemCreated has copy, drop {
        id: ID,
        name: String,
    }

    // ======= Publishing =======
    fun init(ctx: &mut TxContext) {
        share_object(Stores {
            id: object::new(ctx),
            owner_list: vec::empty<address>()
        });
    }

    fun set_quantity(
        s: &mut ItemStore, 
        name: vector<u8>, 
        quantity: u64
    ) {
        let listing_mut = dof::borrow_mut<vector<u8>, ListedItem>(&mut s.id, name);
        option::fill<u64>(&mut listing_mut.quantity, quantity);
    }

    public entry fun create_store(
        name: vector<u8>,
        logo_url: vector<u8>,
        banner_url: vector<u8>,
        description: vector<u8>,
        start_time: u64,
        ctx: &mut TxContext
    ) {
        assert!(start_time > 0, EWrongTime);
        let store_id = object::new(ctx);
        let id_copy = object::uid_to_inner(&store_id);
        let owner_addr = sender(ctx);

        let store = ItemStore {
            id: store_id,
            revenue: 0,
            total_amount: 0,
            name: string::utf8(name),
            logo_url: url::new_unsafe_from_bytes(logo_url),
            banner_url: url::new_unsafe_from_bytes(banner_url),
            description,
            start_time,
            owner: owner_addr,
            paid: balance::zero<SUI>(),
            item_ids: vec::empty<ID>()
        };

        share_object(store);

        let owner_cap = StoreOwnerCap {
            id: object::new(ctx),
            store_id: id_copy
        };

        transfer(
            owner_cap,
            owner_addr
        );
    }

    public entry fun sell(
        s: &mut ItemStore,
        name: vector<u8>,
        description: vector<u8>,
        price: u64,
        quantity: u64,
        url: vector<u8>,
        ctx: &mut TxContext
    ) {
        let seller = sender(ctx);
        assert!(quantity > 0, EAmountIncorrect);
        assert!(seller == s.owner, ENotOwner);

        let item_id = object::new(ctx);
        let id_copy = object::uid_to_inner(&item_id);

        let item = ListedItem {
            id: item_id,
            url: url::new_unsafe_from_bytes(url),
            name: string::utf8(name),
            description: string::utf8(description),
            price,
            quantity: option::none<u64>(),
            buyers: vec::empty<address>()
        };

        dof::add(&mut s.id, name, item); 
        s.total_amount = s.total_amount + quantity;
        set_quantity(s, name, quantity);
        
        vec::push_back(&mut s.item_ids, id_copy);
    }

    fun buy_and_take(
        s: &mut ItemStore, 
        name: vector<u8>, 
        payment: Coin<SUI>, 
        ctx: &mut TxContext
    ) {
        let listing_mut = dof::borrow_mut<vector<u8>, ListedItem>(&mut s.id, name);
        let buyer_addr = sender(ctx);

        assert!(!vec::contains(&listing_mut.buyers, &buyer_addr), EPurchasedItem);
        // check that the Coin amount matches the price;
        assert!(coin::value(&payment) == listing_mut.price, EAmountIncorrect);

        // if quantity is set, make sure that it's not 0; then decrement
        if (option::is_some(&listing_mut.quantity)) {
            let q = option::borrow(&listing_mut.quantity);
            assert!(*q > 0, 0);
            option::swap(&mut listing_mut.quantity, *q - 1);
        };

        let paid = coin::into_balance<SUI>(payment);
        balance::join(&mut s.paid, paid);
        s.revenue = s.revenue + listing_mut.price;
        s.total_amount = s.total_amount - 1;

        let id = object::new(ctx);

        emit(ItemCreated {
            id: object::uid_to_inner(&id),
            name: listing_mut.name
        });

        transfer(Item {
            id,
            url: listing_mut.url,
            name: listing_mut.name,
            description: listing_mut.description,
        }, buyer_addr);

        vec::push_back(&mut listing_mut.buyers, buyer_addr);
    }

    public entry fun buy(
        s: &mut ItemStore, 
        name: vector<u8>, 
        payment: Coin<SUI>, 
        ctx: &mut TxContext
    ) {
        let listing = dof::borrow<vector<u8>, ListedItem>(&mut s.id, name);
        assert!(coin::value(&payment) >= listing.price, EAmountIncorrect);
 
        let paid = coin::split(&mut payment, listing.price, ctx);
        buy_and_take(s, name, paid, ctx);

        transfer(
            payment,
            sender(ctx)
        );
    }

    public entry fun collect_profits(
        s: &mut ItemStore,
        ctx: &mut TxContext
    ) {
        let owner_addr = sender(ctx);
        assert!(owner_addr == s.owner, ENotOwner);

        let revenue_to_collect = balance::value<SUI>(&s.paid);
        let profits = coin::take<SUI>(&mut s.paid, revenue_to_collect, ctx);
        transfer(profits, owner_addr)
    }
}