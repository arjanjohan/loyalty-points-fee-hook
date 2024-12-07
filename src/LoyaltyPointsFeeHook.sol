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
import {IFeeLogic} from "./interfaces/IFeeLogic.sol";

contract LoyaltyPointsFeeHook is BaseHook {
    using LPFeeLibrary for uint24;

    IFeeLogic stylusContract;

    // Error if the pool is not using a dynamic fee
    error MustUseDynamicFee();

    // Initialize BaseHook parent contract in the constructor
    constructor(IPoolManager _poolManager, address _stylusContractAddress) BaseHook(_poolManager) {
        stylusContract = IFeeLogic(_stylusContractAddress);
    }

    function getUserPoints(address user, address currency1) public view returns (uint256) {
        return stylusContract.getUserPoints(user, currency1);
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

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata swapParams, bytes calldata hookData)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {

        address user = abi.decode(hookData, (address));
        uint256 fee = stylusContract.getFee(user, Currency.unwrap(key.currency1));
        uint24 feeWithFlag = uint24(fee) | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feeWithFlag);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        // // If this is not an ETH-TOKEN pool with this hook attached, dont award points
        if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, 0);
        
        address user = abi.decode(hookData, (address));
        stylusContract.updatePoints(user, swapParams.zeroForOne, swapParams.amountSpecified, delta.amount0(), Currency.unwrap(key.currency0), Currency.unwrap(key.currency1));
        return (this.afterSwap.selector, 0);
    }

}
