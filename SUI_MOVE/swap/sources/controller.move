module swap::controller {
    use sui::tx_context::{Self, TxContext};

    use swap::factory::{Self, Global};

    const ERR_NO_PERMISSIONS: u64 = 201;
    const ERR_ALREADY_PAUSE: u64 = 202;
    const ERR_NOT_PAUSE: u64 = 203;

    /// Entrypoint for the `pause` method.
    /// Pause all pools under the global.
    public entry fun pause(global: &mut Global, ctx: &mut TxContext) {
        assert!(!factory::is_emergency(global), ERR_ALREADY_PAUSE);
        assert!(factory::controller(global) == tx_context::sender(ctx), ERR_NO_PERMISSIONS);
        factory::pause(global)
    }

    /// Entrypoint for the `resume` method.
    /// Resume all pools under the global.
    public entry fun resume(global: &mut Global, ctx: &mut TxContext) {
        assert!(factory::is_emergency(global), ERR_NOT_PAUSE);
        assert!(factory::controller(global) == tx_context::sender(ctx), ERR_NO_PERMISSIONS);
        factory::resume(global)
    }
}
