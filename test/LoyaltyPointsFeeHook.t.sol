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
import {LoyaltyPointsFeeHook} from "../src/LoyaltyPointsFeeHook.sol";
import {Stylus} from "../src/Stylus.sol";

contract TestLoyaltyPointsFeeHook is Test, Deployers {


    uint256 constant BASE_FEE = 5000; // 0.5% fee
    uint256 constant HIGH_DISCOUNT = 5000; // 50% discount
    uint256 constant MEDIUM_DISCOUNT = 2500; // 25% discount
    uint256 constant LOW_DISCOUNT = 1000; // 10% discount

    string constant INITIAL_POINTS_ERROR = "Initial points should be 0";
    string constant POINTS_COLLECTED_ERROR = "Points collected should match swap amount";
    string constant SECOND_SWAP_HIGHER_OUTPUT_ERROR = "Second swap should have higher output due to fee discount";
    string constant SWAP_OUTPUT_RATIO_ERROR = "Swap outputs should have expected ratio based on fee discount";
    string constant TOKEN_BALANCE_ERROR = "Token balance change should match swap amount";
    string constant POINTS_EXPIRED_ERROR = "Points should be expired, outputs should match";
    string constant NO_POINTS_COLLECTED_ERROR = "No points should be collected for ERC20-ERC20 swap";







    using CurrencyLibrary for Currency;

    MockERC20 token;

    Currency ethCurrency = Currency.wrap(address(0));

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
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 ethToAdd = 100 ether;

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

    function testPointsCollectedOnZeroForOneSwapExactInput() public {
        uint256 initialPoints = hook.getUserPoints(address(this));
        uint256 initialToken1Balance = currency1.balanceOf(address(this));
        uint256 initialEthBalance = address(this).balance;

        assertEq(initialPoints, 0, INITIAL_POINTS_ERROR);
        
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        uint256 swapAmount = 0.001 ether;

        // First swap - baseline with no points discount
        swapRouter.swap{value: swapAmount}(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount), // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
        uint256 token1BalanceAfterFirstSwap = currency1.balanceOf(address(this));
        uint256 firstSwapTokenOutput = token1BalanceAfterFirstSwap - initialToken1Balance;
        uint256 pointsAfterFirstSwap = hook.getUserPoints(address(this));
        assertEq(pointsAfterFirstSwap, swapAmount, POINTS_COLLECTED_ERROR);

        // Second swap - should have fee discount from accumulated points
        swapRouter.swap{value: swapAmount}(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount), // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 token1BalanceAfterSecondSwap = currency1.balanceOf(address(this));
        uint256 secondSwapTokenOutput = token1BalanceAfterSecondSwap - token1BalanceAfterFirstSwap;

        assertEq(secondSwapTokenOutput > firstSwapTokenOutput, true, SECOND_SWAP_HIGHER_OUTPUT_ERROR);
        assertApproxEqRel(secondSwapTokenOutput, firstSwapTokenOutput * (10000 + (BASE_FEE * HIGH_DISCOUNT / (1000*1000)))/ 10000, 0.001e18, SWAP_OUTPUT_RATIO_ERROR);
    }


    function testPointsCollectedOnOneForZeroSwapExactInput() public {
        uint256 initialPoints = hook.getUserPoints(address(this));
        assertEq(initialPoints, 0, INITIAL_POINTS_ERROR);
        uint256 initialToken1Balance = currency1.balanceOf(address(this));
        uint256 initialEthBalance = address(this).balance;
        
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        uint256 swapAmount = 0.001 ether;

        // First swap - baseline with no points discount
        swapRouter.swap(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(swapAmount), // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 afterToken1Balance = currency1.balanceOf(address(this));
        uint256 firstSwapTokenOutput = initialToken1Balance - afterToken1Balance;
        assertEq(initialToken1Balance - afterToken1Balance, swapAmount, TOKEN_BALANCE_ERROR);
        uint256 firstSwapEthBalance = address(this).balance;

        uint256 ethOutputFirstSwap = firstSwapEthBalance - initialEthBalance;
        uint256 pointsAfterFirstSwap = hook.getUserPoints(address(this));
        assertEq(pointsAfterFirstSwap, ethOutputFirstSwap, POINTS_COLLECTED_ERROR);

        // Second swap - should have fee discount from accumulated points
        swapRouter.swap(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(swapAmount), // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 secondSwapEthBalance = address(this).balance;

        uint256 ethOutputSecondSwap = secondSwapEthBalance - firstSwapEthBalance;

        assertEq(ethOutputSecondSwap > ethOutputFirstSwap, true, SECOND_SWAP_HIGHER_OUTPUT_ERROR);
        assertApproxEqRel(ethOutputSecondSwap, ethOutputFirstSwap * (10000 + (BASE_FEE * HIGH_DISCOUNT / (1000*1000)))/ 10000, 0.002e18, SWAP_OUTPUT_RATIO_ERROR);
    }

    function testPointsCollectedOnOneForZeroSwapExactOutput() public {
        uint256 initialPoints = hook.getUserPoints(address(this));
        assertEq(initialPoints, 0, INITIAL_POINTS_ERROR);
        uint256 initialToken1Balance = currency1.balanceOf(address(this));
        uint256 initialEthBalance = address(this).balance;
        
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        uint256 swapAmount = 0.001 ether;

        // First swap - baseline with no points discount
        swapRouter.swap(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: int256(swapAmount), // Exact output for input swap
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 afterToken1Balance = currency1.balanceOf(address(this));
        uint256 firstSwapTokenInput = initialToken1Balance - afterToken1Balance;
        uint256 afterEthBalance = address(this).balance;

        uint256 ethOutputFirstSwap = afterEthBalance - initialEthBalance;
        uint256 pointsAfterFirstSwap = hook.getUserPoints(address(this));
        assertEq(pointsAfterFirstSwap, ethOutputFirstSwap, POINTS_COLLECTED_ERROR);

        // Second swap - should have fee discount from accumulated points
        swapRouter.swap(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: int256(swapAmount), // Exact output for input swap
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 token1BalanceAfterSecondSwap = currency1.balanceOf(address(this));
        uint256 secondSwapTokenInput = afterToken1Balance - token1BalanceAfterSecondSwap;

        assertEq(secondSwapTokenInput < firstSwapTokenInput, true, SECOND_SWAP_HIGHER_OUTPUT_ERROR);
        assertApproxEqRel(firstSwapTokenInput, secondSwapTokenInput * (10000 + (BASE_FEE * HIGH_DISCOUNT / (1000*1000)))/ 10000, 0.001e18, SWAP_OUTPUT_RATIO_ERROR);
    }

    function testPointsCollectedOnZeroForOneSwapExactOutput() public {
        // Points should equal the amount of eth input
        uint256 ethInputValue = 0.001005125638191961 ether;
        
        
        uint256 initialPoints = hook.getUserPoints(address(this));
        assertEq(initialPoints, 0, INITIAL_POINTS_ERROR);
        uint256 initialToken1Balance = currency1.balanceOf(address(this));
        uint256 initialEthBalance = address(this).balance;
        
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        uint256 swapAmount = 0.001 ether;

        // First swap - baseline with no points discount
        swapRouter.swap{value: ethInputValue}(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: int256(swapAmount), // Exact output for input swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 afterToken1Balance = currency1.balanceOf(address(this));
        uint256 firstSwapTokenOutput = afterToken1Balance - initialToken1Balance;
        assertEq(afterToken1Balance - initialToken1Balance, swapAmount, TOKEN_BALANCE_ERROR);
        uint256 afterFirstSwapEthBalance = address(this).balance;

        uint256 ethInputFirstSwap = initialEthBalance - afterFirstSwapEthBalance;
        assertEq(ethInputFirstSwap, ethInputValue, "ETH input should match expected value");
        uint256 pointsAfterFirstSwap = hook.getUserPoints(address(this));
        assertEq(pointsAfterFirstSwap, ethInputFirstSwap, POINTS_COLLECTED_ERROR);

        // Second swap - should have fee discount from accumulated points
        swapRouter.swap{value: ethInputValue}(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: int256(swapAmount), // Exact output for input swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
        uint256 afterSecondSwapEthBalance = address(this).balance;
        uint256 ethInputSecondSwap = afterFirstSwapEthBalance - afterSecondSwapEthBalance;

        uint256 pointsAfterSecondSwap = hook.getUserPoints(address(this));
        assertEq(pointsAfterSecondSwap, ethInputFirstSwap + ethInputSecondSwap, POINTS_COLLECTED_ERROR);

        assertEq(ethInputFirstSwap > ethInputSecondSwap, true, SECOND_SWAP_HIGHER_OUTPUT_ERROR);
        assertApproxEqRel(ethInputFirstSwap, ethInputSecondSwap * (10000 + (BASE_FEE * HIGH_DISCOUNT / (1000*1000)))/ 10000, 0.001e18, SWAP_OUTPUT_RATIO_ERROR);
    }


    function testPointsExpired() public {
        uint256 initialPoints = hook.getUserPoints(address(this));
        uint256 initialToken1Balance = currency1.balanceOf(address(this));
        uint256 initialEthBalance = address(this).balance;
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        uint256 swapAmount = 0.001 ether;

        // First swap - baseline with no points discount
        swapRouter.swap{value: swapAmount}(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount), // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
        uint256 pointsAfterFirstSwap = hook.getUserPoints(address(this));
        uint256 totalPointsAfterFirstSwap = hook.getTotalPoints();

        uint256 token1BalanceAfterFirstSwap = currency1.balanceOf(address(this));
        uint256 ethBalanceAfterFirstSwap = address(this).balance;
        uint256 firstSwapTokenOutput = token1BalanceAfterFirstSwap - initialToken1Balance;
        assertEq(initialEthBalance - ethBalanceAfterFirstSwap, swapAmount, TOKEN_BALANCE_ERROR);

        // Second swap - should have fee discount from accumulated points
        swapRouter.swap{value: swapAmount}(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount), // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 token1BalanceAfterSecondSwap = currency1.balanceOf(address(this));
        uint256 ethBalanceAfterSecondSwap = address(this).balance;
        uint256 secondSwapTokenOutput = token1BalanceAfterSecondSwap - token1BalanceAfterFirstSwap;
        assertEq(ethBalanceAfterFirstSwap - ethBalanceAfterSecondSwap, swapAmount, TOKEN_BALANCE_ERROR);

        // We expect to get ~0.25% more tokens on the second swap due to fee discount
        // Max delta of 0.001e18 to account for changing price between swaps
        assertEq(secondSwapTokenOutput > firstSwapTokenOutput, true, SECOND_SWAP_HIGHER_OUTPUT_ERROR);
        assertApproxEqRel(secondSwapTokenOutput, firstSwapTokenOutput * (10000 + (BASE_FEE * HIGH_DISCOUNT / (1000*1000)))/ 10000, 0.001e18, SWAP_OUTPUT_RATIO_ERROR);

        // Increase block by 2100 to have points expire
        vm.roll(block.number + 2100);

        // Third swap - points expired, should match first swap output
        swapRouter.swap{value: swapAmount}(
            ethTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount), // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 token1BalanceAfterThirdSwap = currency1.balanceOf(address(this));
        uint256 thirdSwapTokenOutput = token1BalanceAfterThirdSwap - token1BalanceAfterSecondSwap;

        // The third swap should return the same amount as the first, since points have expired
        // Max delta of 0.001e18 to account for changing price between swaps
        assertApproxEqRel(thirdSwapTokenOutput, firstSwapTokenOutput, 0.001e18, POINTS_EXPIRED_ERROR);
    }


    // Test that no points are collected for an ERC20 to ERC20 swap
    function testNoPointsCollectedForERC20ToERC20Swap() public {
        uint256 initialPoints = hook.getUserPoints(address(this));
        uint256 initialToken0Balance = currency0.balanceOf(address(this));
        uint256 initialToken1Balance = currency1.balanceOf(address(this));
        
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        uint256 swapAmount = 0.001 ether;
        // First swap - baseline with no points discount
        swapRouter.swap(
            tokenTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount), // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
        
        uint256 token1BalanceAfterFirstSwap = currency1.balanceOf(address(this));
        uint256 firstSwapTokenOutput = token1BalanceAfterFirstSwap - initialToken1Balance;

        uint256 pointsAfterFirstSwap = hook.getUserPoints(address(this));
        assertEq(pointsAfterFirstSwap, initialPoints, NO_POINTS_COLLECTED_ERROR);
        assertEq(pointsAfterFirstSwap, 0, NO_POINTS_COLLECTED_ERROR);

        // Second swap - again no points discount
        swapRouter.swap(
            tokenTokenKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount), // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 token1BalanceAfterSecondSwap = currency1.balanceOf(address(this));
        uint256 secondSwapTokenOutput = token1BalanceAfterSecondSwap - token1BalanceAfterFirstSwap;
        uint256 pointsAfterSecondSwap = hook.getUserPoints(address(this));
        
        assertEq(pointsAfterSecondSwap, initialPoints, NO_POINTS_COLLECTED_ERROR);
        assertEq(pointsAfterSecondSwap, 0, NO_POINTS_COLLECTED_ERROR);

        // The second swap should return the same amount as the first, since points have expired
        assertApproxEqRel(secondSwapTokenOutput, firstSwapTokenOutput, 0.001e18, POINTS_EXPIRED_ERROR);

        assertApproxEqRel(firstSwapTokenOutput, secondSwapTokenOutput, 0.001e18, POINTS_EXPIRED_ERROR);

       }
}
