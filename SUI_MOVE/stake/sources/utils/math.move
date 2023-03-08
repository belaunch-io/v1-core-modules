// Math implementation for number manipulation.
module belaunch::math {
    const ERR_DIVIDE_BY_ZERO: u64 = 500;
    const ERR_U64_OVERFLOW: u64 = 501;

    const U64_MAX: u64 = 18446744073709551615;

    /// babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    public fun sqrt(y: u128): u128 {
        if (y < 4) {
            if (y == 0) {
                0u128
            } else {
                1u128
            }
        } else {
            let z = y;
            let x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            };
            z
        }
    }

    public fun min(a: u128, b: u128): u128 {
        if (a > b) b else a
    }

    public fun max_u64(a: u64, b: u64): u64 {
        if (a < b) b else a
    }

    public fun max(a: u128, b: u128): u128 {
        if (a < b) b else a
    }

    public fun pow(base: u128, exp: u8): u128 {
        let result = 1u128;
        loop {
            if (exp & 1 == 1) { result = result * base; };
            exp = exp >> 1;
            base = base * base;
            if (exp == 0u8) { break };
        };
        result
    }

    public fun power_decimals(decimals: u64): u64 {
        if (decimals == 0) {
            return 1
        };

        let ret = 10;
        decimals = decimals - 1;
        while (decimals > 0) {
            ret = ret * 10;
            decimals = decimals - 1;
        };
        
        ret
    }

    /// Implements: `x` * `y` / `z`.
    public fun mul_div(
        x: u64,
        y: u64,
        z: u64
    ): u64 {
        assert!(z != 0, ERR_DIVIDE_BY_ZERO);
        let r = (x as u128) * (y as u128) / (z as u128);
        assert!(!(r > (U64_MAX as u128)), ERR_U64_OVERFLOW);
        (r as u64)
    }

    public fun calculate_price<SourceToken, TargetToken>(source_amount: u64, ex_numerator: u64, ex_denominator: u64): u64 {
        // source / src_decimals * target_decimals / (numberator / denominator)
        // let decimals = max((coin::decimals<TargeToken>() as u128), (coin::decimals<SourceToken>() as u128));
        // let decimals = (decimals as u8);
        let ret = (source_amount * ex_denominator as u128)
                  / (ex_numerator as u128);
        (ret as u64)
    }

    // ================ Tests ================
    #[test]
    public fun sqrt_works() {
        assert!(sqrt(4) == 2, 0);
    }
    #[test]
    public fun max_works() {
        assert!(max(4, 12) == 12, 0);
    }

    #[test]
    public fun pow_works() {
        assert!(pow(10, 8) == 100000000, 0);
        assert!(pow(9, 2) == 81, 0);
        assert!(pow(9, 0) == 1, 0);
        assert!(pow(1, 100) == 1, 0);
    }

    #[test]
    public fun power_decimals_works() {
        assert!(power_decimals(2) == 100, 0);
    }
}
