module examples::managed {
    use std::vector;
    use std::option;
    use sui::coin::{Self, Coin, TreasuryCap, value, split, destroy_zero};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::pay;

    /// Name of the coin. By convention, this type has the same name as its parent module
    /// and has no fields. The full type of the coin defined by this module will be `COIN<MANAGED>`.
    struct MANAGED has drop {}

    /// Register the managed currency to acquire its `TreasuryCap`. Because
    /// this is a module initializer, it ensures the currency only gets
    /// registered once.
    fun init(witness: MANAGED, ctx: &mut TxContext) {
        let owner = tx_context::sender(ctx);
        // Get a treasury cap for the coin and give it to the transaction sender
        let (treasury_cap, metadata) = coin::create_currency<MANAGED>(
            witness, 
            2, 
            b"MANAGED", 
            b"MANAGED", 
            b"Managed coin",
            option::none(),
            ctx
        );
        transfer::transfer(treasury_cap, owner);
        transfer::share_object(metadata)
    }

    /// Manager can mint new coins
    public entry fun mint(
        treasury_cap: &mut TreasuryCap<MANAGED>, amount: u64, recipient: address, ctx: &mut TxContext
    ) {
        coin::mint_and_transfer(treasury_cap, amount, recipient, ctx)
    }

    /// Manager can burn coins
    public entry fun burn(treasury_cap: &mut TreasuryCap<MANAGED>, coin: vector<Coin<MANAGED>>, value: u64, ctx: &mut TxContext) {
        // 1. merge coins
        let merged_coins_in = vector::pop_back(&mut coin);
        pay::join_vec(&mut merged_coins_in, coin);
        let coin_in = split(&mut merged_coins_in, value, ctx);

        // 2. burn coin
        coin::burn(treasury_cap, coin_in);

        // 3. handle remain coin
        if (value(&merged_coins_in) > 0) {
            transfer::transfer(
                merged_coins_in,
                tx_context::sender(ctx)
            )
        } else {
            destroy_zero(merged_coins_in)
        }
    }

    /// Manager can renounce ownership
    public entry fun renounce_ownership(
        treasury_cap: TreasuryCap<MANAGED>, _ctx: &mut TxContext
    ) {
        transfer::freeze_object(treasury_cap);
    }

    #[test_only]
    /// Wrapper of module initializer for testing
    public fun test_init(ctx: &mut TxContext) {
        init(MANAGED {}, ctx)
    }
}