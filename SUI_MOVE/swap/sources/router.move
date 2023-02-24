module swap::router {
    use std::vector;

    use sui::coin::{Coin, value, split, destroy_zero};
    use sui::pay;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use swap::event::{added_event, removed_event, swapped_event};
    use swap::factory::{Self, Global, LP};

    use defi::locker::{Locks, add_locked_coins};

    const ERR_NO_PERMISSIONS: u64 = 101;
    const ERR_EMERGENCY: u64 = 102;
    const ERR_GLOBAL_MISMATCH: u64 = 103;
    const ERR_UNEXPECTED_RETURN: u64 = 104;
    const ERR_EMPTY_COINS: u64 = 105;

    /// Entrypoint for the `add_liquidity` method.
    /// Sends `LP<X,Y>` to the transaction sender.
    public entry fun add_liquidity<X, Y>(
        locks: &mut Locks,
        global: &mut Global,
        coin_x: Coin<X>,
        coin_x_min: u64,
        coin_y: Coin<Y>,
        coin_y_min: u64,
        name: vector<u8>,
        logo_url: vector<u8>,
        token_address: vector<u8>,
        decimals: u64,
        unlock_time_secs: u64,
        ctx: &mut TxContext
    ) {
        assert!(!factory::is_emergency(global), ERR_EMERGENCY);
        let is_order = factory::is_order<X, Y>();

        if (!factory::has_registered<X, Y>(global)) {
            factory::register_pool<X, Y>(global, is_order)
        };
        let pool = factory::get_mut_pool<X, Y>(global, is_order);

        let (lp, return_values) = factory::add_liquidity(
            pool,
            coin_x,
            coin_x_min,
            coin_y,
            coin_y_min,
            is_order,
            ctx
        );
        assert!(vector::length(&return_values) == 3, ERR_UNEXPECTED_RETURN);

        let lp_val = vector::pop_back(&mut return_values);
        let coin_x_val = vector::pop_back(&mut return_values);
        let coin_y_val = vector::pop_back(&mut return_values);

        if (unlock_time_secs > 0) {
            let lock_amount: u64 = value(&lp);
            let lock_coins = vector::empty<Coin<LP<X, Y>>>();
            vector::push_back(&mut lock_coins, lp);

            add_locked_coins<LP<X, Y>>(
                locks,
                name,
                logo_url,
                token_address,
                decimals,
                unlock_time_secs,
                lock_coins,
                lock_amount,
                ctx
            )
        } else {
            transfer::transfer(
                lp,
                tx_context::sender(ctx)
            );
        };

        let global = factory::global_id<X, Y>(pool);
        let lp_name = factory::generate_lp_name<X, Y>();

        added_event(
            global,
            lp_name,
            coin_x_val,
            coin_y_val,
            lp_val
        )
    }

    /// Entrypoint for the `remove_liquidity` method.
    /// Transfers Coin<X> and Coin<Y> to the sender.
    public entry fun remove_liquidity<X, Y>(
        global: &mut Global,
        lp_coin: Coin<LP<X, Y>>,
        ctx: &mut TxContext
    ) {
        assert!(!factory::is_emergency(global), ERR_EMERGENCY);
        let is_order = factory::is_order<X, Y>();
        let pool = factory::get_mut_pool<X, Y>(global, is_order);

        let lp_val = value(&lp_coin);
        let (coin_x, coin_y) = factory::remove_liquidity(pool, lp_coin, is_order, ctx);
        let coin_x_val = value(&coin_x);
        let coin_y_val = value(&coin_y);

        transfer::transfer(
            coin_x,
            tx_context::sender(ctx)
        );

        transfer::transfer(
            coin_y,
            tx_context::sender(ctx)
        );

        let global = factory::global_id<X, Y>(pool);
        let lp_name = factory::generate_lp_name<X, Y>();

        removed_event(
            global,
            lp_name,
            coin_x_val,
            coin_y_val,
            lp_val
        )
    }

    /// Entry point for the `swap` method.
    /// Sends swapped Coin to the sender.
    public entry fun swap<X, Y>(
        global: &mut Global,
        coin_in: Coin<X>,
        coin_out_min: u64,
        ctx: &mut TxContext
    ) {
        assert!(!factory::is_emergency(global), ERR_EMERGENCY);
        let is_order = factory::is_order<X, Y>();

        let return_values = factory::swap_out<X, Y>(
            global,
            coin_in,
            coin_out_min,
            is_order,
            ctx
        );

        let coin_y_out = vector::pop_back(&mut return_values);
        let coin_y_in = vector::pop_back(&mut return_values);
        let coin_x_out = vector::pop_back(&mut return_values);
        let coin_x_in = vector::pop_back(&mut return_values);

        let global = factory::id<X, Y>(global);
        let lp_name = factory::generate_lp_name<X, Y>();

        swapped_event(
            global,
            lp_name,
            coin_x_in,
            coin_x_out,
            coin_y_in,
            coin_y_out
        )
    }

    public entry fun multi_add_liquidity<X, Y>(
        locks: &mut Locks,
        global: &mut Global,
        coins_x: vector<Coin<X>>,
        coins_x_value: u64,
        coin_x_min: u64,
        coins_y: vector<Coin<Y>>,
        coins_y_value: u64,
        coin_y_min: u64,
        name: vector<u8>,
        logo_url: vector<u8>,
        token_address: vector<u8>,
        decimals: u64,
        unlock_time_secs: u64,
        ctx: &mut TxContext
    ) {
        assert!(!factory::is_emergency(global), ERR_EMERGENCY);
        assert!(
            !vector::is_empty(&coins_x) && !vector::is_empty(&coins_y),
            ERR_EMPTY_COINS
        );

        // 1. merge coins
        let merged_coin_x = vector::pop_back(&mut coins_x);
        pay::join_vec(&mut merged_coin_x, coins_x);
        let coin_x = split(&mut merged_coin_x, coins_x_value, ctx);

        let merged_coin_y = vector::pop_back(&mut coins_y);
        pay::join_vec(&mut merged_coin_y, coins_y);
        let coin_y = split(&mut merged_coin_y, coins_y_value, ctx);

        // 2. add liquidity
        add_liquidity<X, Y>(
            locks,
            global,
            coin_x,
            coin_x_min,
            coin_y,
            coin_y_min,
            name,
            logo_url,
            token_address,
            decimals,
            unlock_time_secs,
            ctx,
        );

        // 3. handle remain coins
        if (value(&merged_coin_x) > 0) {
            transfer::transfer(
                merged_coin_x,
                tx_context::sender(ctx)
            )
        } else {
            destroy_zero(merged_coin_x)
        };

        if (value(&merged_coin_y) > 0) {
            transfer::transfer(
                merged_coin_y,
                tx_context::sender(ctx)
            )
        } else {
            destroy_zero(merged_coin_y)
        }
    }

    public entry fun multi_remove_liquidity<X, Y>(
        global: &mut Global,
        lp_coin: vector<Coin<LP<X, Y>>>,
        ctx: &mut TxContext
    ) {
        assert!(!factory::is_emergency(global), ERR_EMERGENCY);
        assert!(!vector::is_empty(&lp_coin), ERR_EMPTY_COINS);

        // 1. merge coins
        let merged_lp = vector::pop_back(&mut lp_coin);
        pay::join_vec(&mut merged_lp, lp_coin);

        // 2. remove liquidity
        remove_liquidity(
            global,
            merged_lp,
            ctx
        )
    }

    public entry fun multi_swap<X, Y>(
        global: &mut Global,
        coins_in: vector<Coin<X>>,
        coins_in_value: u64,
        coin_out_min: u64,
        ctx: &mut TxContext
    ) {
        assert!(!factory::is_emergency(global), ERR_EMERGENCY);
        assert!(!vector::is_empty(&coins_in), ERR_EMPTY_COINS);

        // 1. merge coins
        let merged_coins_in = vector::pop_back(&mut coins_in);
        pay::join_vec(&mut merged_coins_in, coins_in);
        let coin_in = split(&mut merged_coins_in, coins_in_value, ctx);

        // 2. swap coin
        swap<X, Y>(
            global,
            coin_in,
            coin_out_min,
            ctx
        );

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
}
