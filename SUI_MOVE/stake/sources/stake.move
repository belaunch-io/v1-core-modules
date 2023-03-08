module belaunch::stake {
    use std::ascii::into_bytes;
    use std::vector as vec;
    use std::string;
    use std::type_name::{get, into_string};

    use sui::coin::{Self, Coin, value, split, destroy_zero};
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::event;
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::object_table::{Self, ObjectTable};
    use sui::pay;
    use sui::dynamic_object_field as dof;
    use sui::url::{Self, Url};

    use belaunch::math;
    use belaunch::comparator;
    use belaunch::u256;

    const DEFAULT_ADMIN: address = @default_admin;
    const DEV: address = @dev;

    // Error codes
    const ERROR_ONLY_ADMIN: u64 = 0;
    const ERROR_POOL_EXIST: u64 = 1;
    const ERROR_COIN_NOT_EXIST: u64 = 2;
    const ERROR_PASS_START_TIME: u64 = 3;
    const ERROR_AMOUNT_TOO_SMALL: u64 = 4;
    const ERROR_POOL_LIMIT_ZERO: u64 = 5;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 6;
    const ERROR_POOL_NOT_EXIST: u64 = 7;
    const ERROR_STAKE_ABOVE_LIMIT: u64 = 8;
    const ERROR_NO_STAKE: u64 = 9;
    const ERROR_NO_LIMIT_SET: u64 = 10;
    const ERROR_LIMIT_MUST_BE_HIGHER: u64 = 11;
    const ERROR_POOL_STARTED: u64 = 12;
    const ERROR_END_TIME_EARLIER_THAN_START_TIME: u64 = 13;
    const ERROR_POOL_END: u64 = 14;
    const ERROR_REWARD_MAX: u64 = 16;
    const ERROR_WRONG_UID: u64 = 17;
    const ERROR_SAME_TOKEN: u64 = 18;
    const ERROR_USER_REGISTERED: u64 = 0;

    // ======= Types =======
    struct StakeOwnerCap has key {
        id: UID,
        admin: address,
    }

    struct PoolInfo<phantom StakeToken, phantom RewardToken> has key {
        id: UID,
        total_staked_token: Balance<StakeToken>,
        total_reward_token: Balance<RewardToken>,
        reward_per_second: u64,
        start_timestamp: u64,
        end_timestamp: u64,
        last_reward_timestamp: u64,
        seconds_for_user_limit: u64,
        pool_limit_per_user: u64,
        acc_token_per_share: u128,
        precision_factor: u128,
        users: ObjectTable<address, UserRegistry<StakeToken, RewardToken>>,
    }

    struct Pools has key {
        id: UID,
        quantity: u64,
    }

    struct ListedPool<phantom StakeToken, phantom RewardToken> has key, store {
        id: UID,
        pool_id: ID,
        coin_type: string::String,
        symbol: string::String,
        logo_url: Url,
        decimals: u64,
        reward_per_second: u64,
        start_timestamp: u64,
        end_timestamp: u64,
        pool_limit_per_user: u64,
        seconds_for_user_limit: u64,
    }

    struct UserInfo<phantom StakeToken, phantom RewardToken> has key, store {
        id: UID,
        amount: u64,
        reward_debt: u128,
        total_rewards_earned: u64,
    }

    struct UserRegistry<phantom StakeToken, phantom RewardToken> has key, store {
        id: UID,
        user: address
    }

    // ======= Events =======
    struct CreatePoolEvent has copy, drop {
        user: address,
        stake_token_info: string::String,
        reward_token_info: string::String,
    }

    struct DepositEvent has copy, drop {
        amount: u64,
    }

    struct WithdrawEvent has copy, drop {
        amount: u64,
    }

    struct EmergencyWithdrawEvent has copy, drop {
        amount: u64,
    }

    struct EmergencyWithdrawRewardEvent has copy, drop {
        admin: address,
        amount: u64,
    }

    struct StopRewardEvent has copy, drop {
        timestamp: u64
    }

    struct NewPoolLimitEvent has copy, drop {
        pool_limit_per_user: u64
    }

    struct NewRewardPerSecondEvent has copy, drop {
        reward_per_second: u64
    }

    struct NewStartAndEndTimestampEvent has copy, drop {
        start_timestamp: u64,
        end_timestamp: u64,
    }

    // ======= Publishing =======
    fun init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);

        transfer::transfer(
            StakeOwnerCap {
                id: object::new(ctx),
                admin: sender,
            }, 
            sender
        );

        transfer::share_object(
            Pools {
                id: object::new(ctx),
                quantity: 0
            }
        )
    }

    public entry fun create_pool<StakeToken, RewardToken>(
        _admin: & StakeOwnerCap,
        pools: &mut Pools,
        symbol: vector<u8>,
        decimals: u64,
        logo_url: vector<u8>,
        reward_per_second: u64,
        start_timestamp: u64,
        end_timestamp: u64,
        pool_limit_per_user: u64,
        seconds_for_user_limit: u64,
        ctx: &mut TxContext
    ) {
        // assert!(start_timestamp > timestamp::now_seconds(), ERROR_PASS_START_TIME);
        assert!(start_timestamp < end_timestamp, ERROR_END_TIME_EARLIER_THAN_START_TIME);
        let comp = comparator::compare(&get<StakeToken>(), &get<RewardToken>());
        assert!(!comparator::is_equal(&comp), ERROR_SAME_TOKEN);

        if (seconds_for_user_limit > 0) {
            assert!(pool_limit_per_user > 0, ERROR_POOL_LIMIT_ZERO);
        };

        let precision_factor = (math::power_decimals(9 - decimals) as u128);

        let admin_address = tx_context::sender(ctx);
        let pool_id = object::new(ctx);
        let id_copy = object::uid_to_inner(&pool_id);
        let pool = PoolInfo<StakeToken, RewardToken> {
            id: pool_id,
            total_staked_token: balance::zero<StakeToken>(),
            total_reward_token: balance::zero<RewardToken>(),
            reward_per_second,
            last_reward_timestamp: start_timestamp,
            start_timestamp,
            end_timestamp,
            seconds_for_user_limit,
            pool_limit_per_user,
            acc_token_per_share: 0,
            precision_factor,
            users: object_table::new<address, UserRegistry<StakeToken, RewardToken>>(ctx)
        };
        transfer::share_object(pool);

        let stake_token_info = string::utf8(b"");
        string::append_utf8(&mut stake_token_info, into_bytes(into_string(get<StakeToken>())));
        let reward_token_info = string::utf8(b"");
        string::append_utf8(&mut reward_token_info, into_bytes(into_string(get<RewardToken>())));

        dof::add(
            &mut pools.id, 
            id_copy, 
            ListedPool<StakeToken, RewardToken> {
                id: object::new(ctx),
                pool_id: id_copy,
                coin_type: reward_token_info,
                symbol: string::utf8(symbol),
                logo_url: url::new_unsafe_from_bytes(logo_url),
                decimals,
                reward_per_second,
                start_timestamp,
                end_timestamp,
                pool_limit_per_user,
                seconds_for_user_limit,
            }
        );
        pools.quantity = pools.quantity + 1;

        event::emit(
            CreatePoolEvent {
                user: admin_address,
                stake_token_info,
                reward_token_info,
            }
        )
    }

    public entry fun add_reward<StakeToken, RewardToken>(
        _admin: & StakeOwnerCap,
        pool: &mut PoolInfo<StakeToken, RewardToken>,
        coins_in: vector<Coin<RewardToken>>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let admin_address = tx_context::sender(ctx);

        // Merge coins
        let merged_coins_in = vec::pop_back(&mut coins_in);
        pay::join_vec(&mut merged_coins_in, coins_in);
        assert!(value(&merged_coins_in) >= amount, ERROR_AMOUNT_TOO_SMALL);

        let coin_in = split(&mut merged_coins_in, amount, ctx);

        let reward_coin_balance = coin::into_balance(coin_in);
        balance::join(&mut pool.total_reward_token, reward_coin_balance);

        // Handle remain coin
        if (value(&merged_coins_in) > 0) {
            transfer::transfer(
                merged_coins_in,
                admin_address
            )
        } else {
            destroy_zero(merged_coins_in)
        }
    }

    public entry fun mint_user_info<StakeToken, RewardToken>(
        pool: &mut PoolInfo<StakeToken, RewardToken>,
        ctx: &mut TxContext
    ) {
        let user_addr = tx_context::sender(ctx);
        assert!(!object_table::contains(&pool.users, user_addr), ERROR_USER_REGISTERED);
        
        let user_info_id = object::new(ctx);

        transfer::transfer(
            UserInfo<StakeToken, RewardToken> {
                id: user_info_id,
                amount: 0,
                reward_debt: 0,
                total_rewards_earned: 0,
            },
            user_addr
        );

        object_table::add(
            &mut pool.users,
            user_addr,
            UserRegistry<StakeToken, RewardToken> {
                id: object::new(ctx),
                user: user_addr,
            },
        );
    }

    public entry fun deposit<StakeToken, RewardToken>(
        pool: &mut PoolInfo<StakeToken, RewardToken>,
        user_info: &mut UserInfo<StakeToken, RewardToken>,
        coins_in: vector<Coin<StakeToken>>,
        amount: u64,
        now: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);
        assert!(pool.end_timestamp > now, ERROR_POOL_END);

        update_pool(pool, now);

        assert!(((user_info.amount + amount) <= pool.pool_limit_per_user) || (now >= (pool.start_timestamp + pool.seconds_for_user_limit)), ERROR_STAKE_ABOVE_LIMIT);

        if (user_info.amount > 0) {
            let pending_reward = cal_pending_reward(user_info.amount, user_info.reward_debt, pool.acc_token_per_share, pool.precision_factor);
            if (pending_reward > 0) {
                let pending_reward_coin = coin::take<RewardToken>(&mut pool.total_reward_token, pending_reward, ctx);
                transfer::transfer(pending_reward_coin, account_address);
                user_info.total_rewards_earned = user_info.total_rewards_earned + pending_reward;
            }
        };

        // Merge coins
        let merged_coins_in = vec::pop_back(&mut coins_in);
        pay::join_vec(&mut merged_coins_in, coins_in);
        assert!(value(&merged_coins_in) >= amount, ERROR_AMOUNT_TOO_SMALL);

        let coin_in = split(&mut merged_coins_in, amount, ctx);

        let staked_coin_balance = coin::into_balance(coin_in);
        balance::join(&mut pool.total_staked_token, staked_coin_balance);

        // Handle remain coin
        if (value(&merged_coins_in) > 0) {
            transfer::transfer(
                merged_coins_in,
                account_address
            )
        } else {
            destroy_zero(merged_coins_in)
        };

        user_info.amount = user_info.amount + amount;
        user_info.reward_debt = reward_debt(user_info.amount, pool.acc_token_per_share, pool.precision_factor);

        event::emit(
            DepositEvent {
                amount
            }
        )
    }

    public entry fun withdraw<StakeToken, RewardToken>(
        pool: &mut PoolInfo<StakeToken, RewardToken>,
        user_info: &mut UserInfo<StakeToken, RewardToken>,
        amount: u64,
        now: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        update_pool(pool, now);

        assert!(user_info.amount >= amount, ERROR_INSUFFICIENT_BALANCE);

        let pending_reward = cal_pending_reward(user_info.amount, user_info.reward_debt, pool.acc_token_per_share, pool.precision_factor);

        if (amount > 0) {
            user_info.amount = user_info.amount - amount;

            let staked_coin = coin::take<StakeToken>(&mut pool.total_staked_token, amount, ctx);
            transfer::transfer(staked_coin, account_address);
        };

        if (pending_reward > 0) {
            let pending_reward_coin = coin::take<RewardToken>(&mut pool.total_reward_token, pending_reward, ctx);
            transfer::transfer(pending_reward_coin, account_address);
            user_info.total_rewards_earned = user_info.total_rewards_earned + pending_reward;
        };

        user_info.reward_debt = reward_debt(user_info.amount, pool.acc_token_per_share, pool.precision_factor);

        event::emit(
            WithdrawEvent {
                amount
            }
        )
    }

    public entry fun emergency_withdraw<StakeToken, RewardToken>(    
        pool: &mut PoolInfo<StakeToken, RewardToken>,
        user_info: &mut UserInfo<StakeToken, RewardToken>,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        let amount = user_info.amount;
        assert!(amount > 0, ERROR_INSUFFICIENT_BALANCE);

        user_info.amount = 0;
        user_info.reward_debt = 0;

        let staked_coin = coin::take<StakeToken>(&mut pool.total_staked_token, amount, ctx);
        transfer::transfer(staked_coin, account_address);

        event::emit(
            EmergencyWithdrawEvent {
                amount
            }
        )
    }

    public entry fun emergency_reward_withdraw<StakeToken, RewardToken>(
        _admin: & StakeOwnerCap,
        pool: &mut PoolInfo<StakeToken, RewardToken>,
        ctx: &mut TxContext
    ) {
        let admin_address = tx_context::sender(ctx);

        let reward = balance::value(&pool.total_reward_token);
        assert!(reward > 0, ERROR_INSUFFICIENT_BALANCE);

        let reward_coin = coin::take<RewardToken>(&mut pool.total_reward_token, reward, ctx);
        transfer::transfer(reward_coin, admin_address);

        event::emit(
            EmergencyWithdrawRewardEvent {
                admin: admin_address,
                amount: reward,
            }
        )
    }

    public entry fun stop_reward<StakeToken, RewardToken>(
        _admin: & StakeOwnerCap,
        pool: &mut PoolInfo<StakeToken, RewardToken>,
        now: u64,
        _ctx: &mut TxContext,
    ) {
        pool.end_timestamp = now;

        event::emit(
            StopRewardEvent {
                timestamp: now,
            }
        )
    }

    public entry fun update_pool_limit_per_user<StakeToken, RewardToken, UID>(        
        _admin: & StakeOwnerCap,
        pool: &mut PoolInfo<StakeToken, RewardToken>, 
        seconds_for_user_limit: bool, 
        pool_limit_per_user: u64,
        now: u64,
        _ctx: &mut TxContext,
    ) { 
        assert!((pool.seconds_for_user_limit > 0) && (now < (pool.start_timestamp + pool.seconds_for_user_limit)), ERROR_NO_LIMIT_SET);
        if (seconds_for_user_limit) {
            assert!(pool_limit_per_user > pool.pool_limit_per_user, ERROR_LIMIT_MUST_BE_HIGHER);
            pool.pool_limit_per_user = pool_limit_per_user
        } else {
            pool.seconds_for_user_limit = 0;
            pool.pool_limit_per_user = 0
        };

        event::emit(
            NewPoolLimitEvent {
                pool_limit_per_user: pool.pool_limit_per_user
            }
        )
    }

    public entry fun update_reward_per_second<StakeToken, RewardToken, UID>(
        _admin: & StakeOwnerCap,
        pool: &mut PoolInfo<StakeToken, RewardToken>, 
        reward_per_second: u64,
        now: u64,
        _ctx: &mut TxContext,
    ) {
        assert!(now < pool.start_timestamp, ERROR_POOL_STARTED);
        pool.reward_per_second = reward_per_second;

        event::emit(
            NewRewardPerSecondEvent {
                reward_per_second
            }
        )
    }

    public entry fun update_start_and_end_timestamp<StakeToken, RewardToken, UID>(
        _admin: & StakeOwnerCap,
        pool: &mut PoolInfo<StakeToken, RewardToken>, 
        start_timestamp: u64, 
        end_timestamp: u64,
        now: u64,
        _ctx: &mut TxContext,
    ) {
        assert!(now < pool.start_timestamp, ERROR_POOL_STARTED);
        assert!(start_timestamp < end_timestamp, ERROR_END_TIME_EARLIER_THAN_START_TIME);
        assert!(now < start_timestamp, ERROR_PASS_START_TIME);

        pool.start_timestamp = start_timestamp;
        pool.end_timestamp = end_timestamp;

        pool.last_reward_timestamp = start_timestamp;

        event::emit(
            NewStartAndEndTimestampEvent {
                start_timestamp,
                end_timestamp
            }
        )
    }

    public fun get_pool_info<StakeToken, RewardToken>(pool: & PoolInfo<StakeToken, RewardToken>): (u64, u64, u64, u64, u64, u64, u64) {
        (
            balance::value(&pool.total_staked_token),
            balance::value(&pool.total_reward_token),
            pool.reward_per_second,
            pool.start_timestamp,
            pool.end_timestamp,
            pool.seconds_for_user_limit,
            pool.pool_limit_per_user,
        )
    }

    public fun get_user_stake_amount<StakeToken, RewardToken>(user_info: & UserInfo<StakeToken, RewardToken>): u64 {
        user_info.amount
    }

    public fun get_pending_reward<StakeToken, RewardToken>(
        pool: & PoolInfo<StakeToken, RewardToken>,
        user_info: & UserInfo<StakeToken, RewardToken>,
        now: u64,
    ): u64 {
        let acc_token_per_share = if (balance::value(&pool.total_staked_token) == 0 || now < pool.last_reward_timestamp) {
            pool.acc_token_per_share
        } else {
            cal_acc_token_per_share(
                pool.acc_token_per_share,
                balance::value(&pool.total_staked_token),
                pool.end_timestamp,
                pool.reward_per_second,
                pool.precision_factor,
                pool.last_reward_timestamp,
                now
            )
        };
        cal_pending_reward(user_info.amount, user_info.reward_debt, acc_token_per_share, pool.precision_factor)
    }

    fun update_pool<StakeToken, RewardToken>(pool: &mut PoolInfo<StakeToken, RewardToken>, now: u64) {
        if (now <= pool.last_reward_timestamp) return;

        if (balance::value(&pool.total_staked_token) == 0) {
            pool.last_reward_timestamp = now;
            return
        };

        let new_acc_token_per_share = cal_acc_token_per_share(
            pool.acc_token_per_share,
            balance::value(&pool.total_staked_token),
            pool.end_timestamp,
            pool.reward_per_second,
            pool.precision_factor,
            pool.last_reward_timestamp,
            now
        );

        if (pool.acc_token_per_share == new_acc_token_per_share) return;
        pool.acc_token_per_share = new_acc_token_per_share;
        pool.last_reward_timestamp = now;
    }

    fun cal_acc_token_per_share(
        last_acc_token_per_share: u128, 
        total_staked_token: u64, 
        end_timestamp: u64, 
        reward_per_second: u64, 
        precision_factor: u128, 
        last_reward_timestamp: u64, 
        now: u64
    ): u128 {
        let multiplier = get_multiplier(last_reward_timestamp, now, end_timestamp);
        let reward = u256::from_u128((reward_per_second as u128) * (multiplier as u128));
        if (multiplier == 0) return last_acc_token_per_share;
        // acc_token_per_share = acc_token_per_share + (reward * precision_factor) / total_stake;
        let acc_token_per_share_u256 = u256::add(
            u256::from_u128(last_acc_token_per_share),
            u256::div(
                u256::mul(reward, u256::from_u128(precision_factor)),
                u256::from_u64(total_staked_token)
            )
        );
        u256::as_u128(acc_token_per_share_u256)
    }

    fun cal_pending_reward(amount: u64, reward_debt: u128, acc_token_per_share: u128, precision_factor: u128): u64 {
        // pending = (user_info::amount * pool_info.acc_token_per_share) / pool_info.precision_factor - user_info.reward_debt
        u256::as_u64(
            u256::sub(
                u256::div(
                    u256::mul(
                        u256::from_u64(amount),
                        u256::from_u128(acc_token_per_share)
                    ), u256::from_u128(precision_factor)
                ), u256::from_u128(reward_debt))
        )
    }

    fun reward_debt(amount: u64, acc_token_per_share: u128, precision_factor: u128): u128 {
        // user.reward_debt = (user_info.amount * pool_info.acc_token_per_share) / pool_info.precision_factor;
        u256::as_u128(
            u256::div(
                u256::mul(
                    u256::from_u64(amount),
                    u256::from_u128(acc_token_per_share)
                ),
                u256::from_u128(precision_factor)
            )
        )
    }

    fun get_multiplier(from_timestamp: u64, to_timestamp: u64, end_timestamp: u64): u64 {
        if (to_timestamp <= end_timestamp) {
            to_timestamp - from_timestamp
        } else if (from_timestamp >= end_timestamp) {
            0
        } else {
            end_timestamp - from_timestamp
        }
    }
}