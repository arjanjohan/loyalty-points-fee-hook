## Loyalty Points Fee Hook

The Loyalty Points Fee Hook is a Uniswap V4 hook that tracks of the volume traded and LP provided by users. Users are awarded points, which can give a discount on trading fees in pools with this hook attached.

⚙️ Built using Solidity, Uniswap and Foundry

- 🌟 **Earn Points**: Earn loyalty points by trading in the pool or providing liquidity. Higher gas prices mean more points earned per transaction.
- 💰 **Dynamic Fees**: Get discounted trading fees based on your points balance. The more points you have, the lower your fees.
- ⏰ **Stay Active**: Points expire over time unless you remain active in the pool through trading or liquidity provision.
- ⛽ **Gas Bonus**: Earn bonus points during high gas periods to reward users who help maintain pool activity when network is congested.

## Instructions

// todo

## Hook description

This hook is built on top of [Uniswap V4 Template](https://github.com/uniswapfoundation/v4-template).


1. The Loyalty Points Fee hook [LoyaltyPointsFeeHook.sol](src/LoyaltyPointsFeeHook.sol) uses:
    - `constructor` takes _baseFee and _expirationBlocks as arguments to determine the base fee (without discount) and how many blocks of inactivity will makes points expire.
    - `beforeSwap()` hook first checks the users most recent activity. If the user has been inactive too long, his points are reset. Then it calculates the fee with via the implementation written in [Stylus](TODO),
    - `afterSwap()` hook calculates the amount of points earned with the swap,
    <!-- - `beforeAddLiquidity()` hook, -->
    <!-- - `beforeRemoveLiquidity()` hook, -->
    - `getHookPermissions()` function.
2. The test template [LoyaltyPointsFeeHook.t.sol](test/LoyaltyPointsFeeHook.t.sol) preconfigures the v4 pool manager, test tokens, and test liquidity.

## Next steps

I will implement first a basic version of the hook, then keep adding more sophisticated features along the way.
<!-- - Hook that awards points for amount of input tokens (ignoring token prices) -->
- Calculate a uniform price for points based on TOKEN/ETH or TOKEN/USD price
<!-- - Fixed discount if points > threshold -->
- Discount based on amount of points
- Points expire after x blocks have passed
- Earn more points when gas is high

## Links
- [Deployed Hook Contract]()
- [Demo video]()

## Team 
- [arjanjohan](https://x.com/arjanjohan)
