//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../contracts/LoyaltyPointsFeeHook.sol";
import "../contracts/Stylus.sol";
import "./DeployHelpers.s.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "../test/HookMiner.sol";

contract DeployYourContract is ScaffoldETHDeploy {


    PoolManager manager =
        PoolManager(0xCa6DBBe730e31fDaACaA096821199EEED5AD84aE);

   // use `deployer` from `ScaffoldETHDeploy`
  function run() external ScaffoldEthDeployerRunner {


    // Stylus stylusContract = new Stylus(100, 500000);

		// Set up the hook flags you wish to enable
        uint160 flags = uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
            

		// Find an address + salt using HookMiner that meets our flags criteria
        address CREATE2_DEPLOYER = 0x199d51a2Be04C65f325908911430E6FF79a15ce3;
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(LoyaltyPointsFeeHook).creationCode,
            abi.encode(address(manager))
        );

		// Deploy our hook contract with the given `salt` value
        // LoyaltyPointsFeeHook hook = new LoyaltyPointsFeeHook(manager, address(stylusContract));
      LoyaltyPointsFeeHook hook = new LoyaltyPointsFeeHook{salt: salt}(manager, address(0));
		// Ensure it got deployed to our pre-computed address
        // require(address(hook) == hookAddress, "hook address mismatch");
  }
}
