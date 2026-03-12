// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract BridgeUpgradeScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("NETWORK_PRIVATE_KEY");
        address stakeManagerProxy = vm.envOr("STAKE_MANAGER_PROXY", address(0));
        address validatorManagerProxy = vm.envOr("VALIDATOR_MANAGER_PROXY", address(0));
        string memory referenceBuildInfoDir = vm.envString("REFERENCE_BUILD_INFO_DIR");
        string memory referenceBuildInfoDirName = vm.envString("REFERENCE_BUILD_INFO_DIR_NAME");

        require(
            stakeManagerProxy != address(0) || validatorManagerProxy != address(0),
            "no upgradeable proxies configured"
        );

        vm.startBroadcast(deployerPrivateKey);

        if (stakeManagerProxy != address(0)) {
            _upgradeProxy(
                stakeManagerProxy,
                "StakeManager.sol",
                string.concat(referenceBuildInfoDirName, ":StakeManager"),
                referenceBuildInfoDir
            );
        }

        if (validatorManagerProxy != address(0)) {
            _upgradeProxy(
                validatorManagerProxy,
                "ValidatorManager.sol",
                string.concat(referenceBuildInfoDirName, ":ValidatorManager"),
                referenceBuildInfoDir
            );
        }

        vm.stopBroadcast();
    }

    function _upgradeProxy(
        address proxy,
        string memory contractName,
        string memory referenceContract,
        string memory referenceBuildInfoDir
    )
        internal
    {
        Options memory options;
        options.referenceBuildInfoDir = referenceBuildInfoDir;
        options.referenceContract = referenceContract;
        options.unsafeAllow = "internal-function-storage";

        address previousImplementation = Upgrades.getImplementationAddress(proxy);
        Upgrades.upgradeProxy(proxy, contractName, "", options);
        address newImplementation = Upgrades.getImplementationAddress(proxy);

        console.log("Upgraded proxy:", proxy);
        console.log("  Contract:", contractName);
        console.log("  Previous implementation:", previousImplementation);
        console.log("  New implementation:", newImplementation);
    }
}
