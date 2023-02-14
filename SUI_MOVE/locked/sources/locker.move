module defi::locker {
    use sui::balance::{Self, Balance};
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::url::{Self, Url};

    use std::vector as vec;
    use std::string::{Self, String};

    // ======= Types =======
    struct OwnerCap has key, store { id: UID }

    /// Represents a lock of coins until some specified unlock time. Afterward, the recipient can claim the coins.
    struct Lock<phantom CoinType> has key, store {
        id: UID,
        name: String,
        logo_url: Url,
        owner: address,
        token_address: String,
        decimals: u64,
        amount: u64,
        balance: Balance<CoinType>,
        unlock_time_secs: u64,
        is_claim: bool
    }

    struct Locks has key, store {
        id: UID,
        lock_list: vector<ID>
    }

    // ======= Events =======
    /// Event emitted when a recipient claims unlocked coins.
    struct ClaimEvent has copy, drop {
        recipient: address,
        amount: u64,
        claimed_time_secs: u64,
    }

    // Error codes
    /// No locked coins found to claim.
    const ELOCK_NOT_FOUND: u64 = 1;
    /// Lockup has not expired yet.
    const ELOCKUP_HAS_NOT_EXPIRED: u64 = 2;
    /// Can only create one active lock per recipient at once.
    const ELOCK_ALREADY_EXISTS: u64 = 3;
    /// The length of the recipients list doesn't match the amounts.
    const EINVALID_RECIPIENTS_LIST_LENGTH: u64 = 3;
    const EINVALID_TIME: u64 = 4;

    // ======= Publishing =======
    fun init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let id = object::new(ctx);

        transfer::transfer(
            OwnerCap {
                id
            },
            sender
        );

        transfer::share_object(Locks {
            id: object::new(ctx),
            lock_list: vec::empty<ID>()
        })
    }

    public entry fun mint_user_lock<CoinType>(
        locks: &mut Locks, 
        name: vector<u8>,
        logo_url: vector<u8>,
        token_address: vector<u8>,
        decimals: u64,
        unlock_time_secs: u64, 
        ctx: &mut TxContext
    ) {
        let user_addr = tx_context::sender(ctx);
        let user_info_id = object::new(ctx);
        let id_copy = object::uid_to_inner(&user_info_id);

        let lock = Lock<CoinType> {
            id: user_info_id,
            name: string::utf8(name),
            logo_url: url::new_unsafe_from_bytes(logo_url),
            owner: user_addr,
            token_address: string::utf8(token_address),
            decimals: decimals,
            amount: 0,
            balance: balance::zero<CoinType>(),
            unlock_time_secs: unlock_time_secs,
            is_claim: false,
        };

        transfer::transfer(lock, user_addr);

        vec::push_back(&mut locks.lock_list, id_copy);
    }

    public entry fun add_locked_coins<CoinType>(
        lock: &mut Lock<CoinType>,
        coin: &mut Coin<CoinType>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let locked_coin = coin::split(coin, amount, ctx);
        let locked_balance = coin::into_balance(locked_coin);
        
        // Update lock information
        balance::join(&mut lock.balance, locked_balance);
        lock.amount = lock.amount + amount;
    }

    public entry fun claim<CoinType>(
        lock_info: &mut Lock<CoinType>,
        ctx: &mut TxContext
    ) {
        let recipient_address = tx_context::sender(ctx);
        let time_now = tx_context::epoch(ctx);
        // assert!(time_now >= lock_info.unlock_time_secs, ELOCKUP_HAS_NOT_EXPIRED);

        let locked_balance = balance::value<CoinType>(&lock_info.balance);
        let claim = coin::take<CoinType>(&mut lock_info.balance, locked_balance, ctx);
        transfer::transfer(claim, recipient_address);

        lock_info.is_claim = true;

        event::emit(
            ClaimEvent {
                recipient: recipient_address,
                amount: locked_balance,
                claimed_time_secs: time_now,
            }
        );
    }

    public entry fun update_name<CoinType>(
        lock_info: &mut Lock<CoinType>,
        name: String,
        _ctx: &mut TxContext
    ) {
       lock_info.name = name;
    }

    public entry fun update_time<CoinType>(
        lock_info: &mut Lock<CoinType>,
        unlock_time: u64,
        _ctx: &mut TxContext
    ) {
        assert!(unlock_time > lock_info.unlock_time_secs, EINVALID_TIME);
        lock_info.unlock_time_secs = unlock_time;
    }
}