// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {Insurance} from "../src/Insurance.sol";

contract InsuranceScript is Script {
    Insurance public insurance;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        insurance = new Insurance();

        // Optional: You can add initial managers here if needed
        // insurance.addManager(address(0xYourManagerAddress));

        vm.stopBroadcast();
    }
}
