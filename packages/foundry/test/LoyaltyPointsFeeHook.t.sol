// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import "forge-std/console.sol";
import {LoyaltyPointsFeeHook} from "../contracts/LoyaltyPointsFeeHook.sol";
import {Stylus} from "../contracts/Stylus.sol";

contract TestLoyaltyPointsFeeHook is Test, Deployers {
    using CurrencyLibrary for Currency;

    MockERC20 token;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    LoyaltyPointsFeeHook hook;
    
    PoolKey tokenTokenKey;
    PoolKey ethTokenKey;

    function setUp() public {
        // Deploy v4-core
        deployFreshManagerAndRouters();

        // Deploy, mint tokens, and approve all periphery contracts for two tokens
        deployMintAndApprove2Currencies();

        // Deploy our hook with the proper flags
        address hookAddress =
            address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG));

        // Set gas price = 10 gwei and deploy our hook
        vm.txGasPrice(10 gwei);
        address stylusAddress = address(new Stylus(5000, 2000));
        deployCodeTo("LoyaltyPointsFeeHook.sol", abi.encode(manager, stylusAddress), hookAddress);
        hook = LoyaltyPointsFeeHook(hookAddress);

        // Initialize token-token pool
        (tokenTokenKey,) = initPool(
            currency0,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // Set the `DYNAMIC_FEE_FLAG` in place of specifying a fixed fee
            SQRT_PRICE_1_1
        );

        // Add some liquidity to token-token pool
        modifyLiquidityRouter.modifyLiquidity(
            tokenTokenKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 ethToAdd = 10 ether;

        // Initialize eth-token pool
        (ethTokenKey,) = initPool(
            ethCurrency,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // Set the `DYNAMIC_FEE_FLAG` in place of specifying a fixed fee
            SQRT_PRICE_1_1
        );

        // Add some liquidity to eth-token pool
        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            ethTokenKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_pointsCollectedOnZeroForOneSwapNegative() public {
        uint256 initialPoints = hook.getUserPoints(address(this));
        uint256 initialToken1Balance = currency1.balanceOf(address(this));
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // First swap - baseline with no points discount
        swapRouter.swap{value: 0.001 ether}(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
        uint256 pointsAfterFirstSwap = hook.getUserPoints(address(this));
        uint256 totalPointsAfterFirstSwap = hook.getTotalPoints();

        uint256 token1BalanceAfterFirstSwap = currency1.balanceOf(address(this));
        uint256 firstSwapTokenOutput = token1BalanceAfterFirstSwap - initialToken1Balance;

        // Second swap - should have fee discount from accumulated points
        swapRouter.swap{value: 0.001 ether}(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 token1BalanceAfterSecondSwap = currency1.balanceOf(address(this));
        uint256 secondSwapTokenOutput = token1BalanceAfterSecondSwap - token1BalanceAfterFirstSwap;

        // We expect to get ~0.25% more tokens on the second swap due to fee discount
        assertApproxEqRel(secondSwapTokenOutput, firstSwapTokenOutput * 10025 / 10000, 0.001e18);

        // Increase block by 2100 to have points expire
        vm.roll(block.number + 2100);

        // Third swap - points expired, should match first swap output
        swapRouter.swap{value: 0.001 ether}(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 token1BalanceAfterThirdSwap = currency1.balanceOf(address(this));
        uint256 thirdSwapTokenOutput = token1BalanceAfterThirdSwap - token1BalanceAfterSecondSwap;

        // The third swap should return the same amount as the first, since points have expired
        assertApproxEqRel(thirdSwapTokenOutput, firstSwapTokenOutput, 0.001e18);
    }

    function test_pointsCollectedOnZeroForOneSwapPositive() public {
        uint256 pointsBalanceOriginal = hook.getUserPoints(address(this));

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // Now we swap
        // We will swap 0.001 ether for tokens
        // We should get 0.001 ether in points
        swapRouter.swap(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: 0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
        // uint256 pointsBalanceAfterSwap = hook.getUserPoints(address(this));
        // uint256 totalPoints = hook.getTotalPoints();
        // uint256 EXPECTED_POINTS = 1005035175979902;
        // assertEq(totalPoints, EXPECTED_POINTS);
        // assertEq(pointsBalanceAfterSwap, pointsBalanceOriginal + EXPECTED_POINTS);
    }
}