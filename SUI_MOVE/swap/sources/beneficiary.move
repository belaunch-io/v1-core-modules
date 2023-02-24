module swap::beneficiary {
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use swap::event::withdrew_event;
    use swap::factory::{Self, Global};

    const ERR_NO_PERMISSIONS: u64 = 301;
    const ERR_EMERGENCY: u64 = 302;
    const ERR_GLOBAL_MISMATCH: u64 = 303;

    /// Entrypoint for the `withdraw` method.
    /// Transfers withdrew fee coins to the beneficiary.
    public entry fun withdraw<X, Y>(
        global: &mut Global,
        ctx: &mut TxContext
    ) {
        assert!(!factory::is_emergency(global), ERR_EMERGENCY);
        assert!(factory::beneficiary(global) == tx_context::sender(ctx), ERR_NO_PERMISSIONS);

        let pool = factory::get_mut_pool<X, Y>(global, factory::is_order<X, Y>());
        let (coin_x, coin_y, fee_coin_x, fee_coin_y) = factory::withdraw(pool, ctx);

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

        withdrew_event(
            global,
            lp_name,
            fee_coin_x,
            fee_coin_y
        )
    }
}
