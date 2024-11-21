// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract LoyaltyPointsFeeHook is BaseHook {
    using LPFeeLibrary for uint24;

    // The default base fees we will charge
    uint24 public constant BASE_FEE = 5000; // denominated in pips (one-hundredth bps) 0.5%

    uint256 public constant POINTS_EXPIRATION_BLOCKS = 2000;

    // Error if the pool is not using a dynamic fee
    error MustUseDynamicFee();

    // Initialize BaseHook parent contract in the constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    // mapping of address to points
    mapping(address => uint256) public points;
    // mapping of address to last activity block
    mapping(address => uint256) public lastActivityBlock;
    uint256 totalPoints;

    function getTotalPoints() public view returns (uint256) {
        return totalPoints;
    }

    // Required override function for BaseHook to let the PoolManager know which hooks are implemented
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeInitialize(address, PoolKey calldata key, uint160) external pure override returns (bytes4) {
        // `.isDynamicFee()` function comes from using
        // the `SwapFeeLibrary` for `uint24`
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {   
        // Reset points if user has not been active for a while
        if (block.number - lastActivityBlock[msg.sender] > POINTS_EXPIRATION_BLOCKS) {
            points[msg.sender] = 0;
        }

        uint24 fee = getFee();
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feeWithFlag);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {


        // // If this is not an ETH-TOKEN pool with this hook attached, ignore
        // if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, 0);

        if (swapParams.zeroForOne) {
            if (swapParams.amountSpecified < 0) {
                // token0 is being sold, amountSpecified is exact input
                calculatePoints(-swapParams.amountSpecified, key.currency0);
            } else {
                // token1 is being sold, amountSpecified is exact output
                calculatePoints(-delta.amount0(), key.currency0);
            }
        } else {
            if (swapParams.amountSpecified > 0) {
                // token1 is being sold, amountSpecified is exact input
                calculatePoints(swapParams.amountSpecified, key.currency1);
            } else {
                // token1 is being sold, amountSpecified is exact output
                // TODO Test if amount is correct
                calculatePoints(delta.amount0(), key.currency1);
            }
        }
        lastActivityBlock[msg.sender] = block.number;
        
        return (this.afterSwap.selector, 0);
    }

    function getFee() internal view returns (uint24) {
        uint256 userPoints = points[msg.sender];

        // if fees above threshold, give discount
        if (userPoints > 200) {
            return BASE_FEE / 2;
        }

        return BASE_FEE;
    }

    function calculatePoints(int256 amountIn, Currency tokenIn) internal {
        // TODO: convert amountIn to ETH for a more fair points calculation
        points[msg.sender] += uint256(amountIn);
        totalPoints += uint256(amountIn);
    }
}

// todo:
// high gas price => earn more points
// points expire if unused (like in airline)
