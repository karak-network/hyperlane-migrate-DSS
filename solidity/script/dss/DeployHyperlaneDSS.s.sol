// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import {ProxyAdmin} from "../../contracts/upgrade/ProxyAdmin.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "../../contracts/upgrade/TransparentUpgradeableProxy.sol";

import {HyperlaneDSS, HyperlaneDSSLib} from "../../contracts/DSS/HyperlaneDSS.sol";
import {Constants} from "../../contracts/DSS/entities/Constants.sol";

contract DeployHyperlaneDSS is Script {
    using stdJson for string;

    address hyperlaneDSSOwner;
    address coreAddress;
    uint256 minimumWeight;
    uint256 maxSlashablePercentageWad;
    address DEPLOYER = 0x54603E6fd3A92E32Bd3c00399D306B82bB3601Ba;
    address PROXY_ADMIN_OWNER = 0x54603E6fd3A92E32Bd3c00399D306B82bB3601Ba;

    HyperlaneDSSLib.Quorum quorum;
    ProxyAdmin proxyAdmin;
    HyperlaneDSS hyperlaneDSS;

    function loadConfig(string memory network) internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/script/dss/karak_addresses.json"
        );
        string memory json = vm.readFile(path);

        coreAddress = json.readAddress(
            string(abi.encodePacked(".", network, ".coreAddress"))
        );
        hyperlaneDSSOwner = json.readAddress(
            string(abi.encodePacked(".", network, ".hyperlaneDSSOwner"))
        );
        minimumWeight = json.readUint(
            string(abi.encodePacked(".", network, ".minimumWeight"))
        );
        maxSlashablePercentageWad = json.readUint(
            string(abi.encodePacked(".", network, ".maxSlashablePercentageWad"))
        );

        HyperlaneDSSLib.AssetParams[] memory assets = abi.decode(
            vm.parseJson(
                json,
                string(abi.encodePacked(".", network, ".quorum"))
            ),
            (HyperlaneDSSLib.AssetParams[])
        );

        uint96 weightSum = 0;

        for (uint256 i = 0; i < assets.length; i++) {
            // validate sum of assets weight
            weightSum += assets[i].weight;
            quorum.assets.push(assets[i]);
        }
        require(weightSum == Constants.BPS, "Invalid sum of asset weights");
    }

    function deployProxyAdmin() public {
        vm.startBroadcast(PROXY_ADMIN_OWNER);
        proxyAdmin = new ProxyAdmin();
        vm.stopBroadcast();
        require(
            PROXY_ADMIN_OWNER == proxyAdmin.owner(),
            "Invalid owner of proxyAdmin"
        );
        console2.log("deployed proxyAdmin at:", address(proxyAdmin));
    }

    function deployHyperlaneDSSAsTransparentProxy() public {
        vm.startBroadcast(DEPLOYER);
        address hyperlaneDSSImpl = address(new HyperlaneDSS());
        hyperlaneDSS = HyperlaneDSS(
            address(
                new TransparentUpgradeableProxy(
                    hyperlaneDSSImpl,
                    address(proxyAdmin),
                    ""
                )
            )
        );
        vm.stopBroadcast();
        require(
            proxyAdmin.getProxyImplementation(
                ITransparentUpgradeableProxy(address(hyperlaneDSS))
            ) == hyperlaneDSSImpl,
            "Invalid implementation"
        );
        require(
            proxyAdmin.getProxyAdmin(
                ITransparentUpgradeableProxy(address(hyperlaneDSS))
            ) == address(proxyAdmin),
            "Invalid proxyAdmin"
        );
        console2.log("Hyperlane proxy", address(hyperlaneDSS));
    }

    function initializeHyperlaneDSS(string memory network) public {
        vm.startBroadcast(DEPLOYER);
        hyperlaneDSS.initialize(
            hyperlaneDSSOwner,
            coreAddress,
            minimumWeight,
            quorum
        );
        vm.stopBroadcast();
        console2.log("sucessfully initialized hyperlaneDSS");
    }

    function registerHyperlaneDSS() public {
        vm.startBroadcast(hyperlaneDSSOwner);
        hyperlaneDSS.registerToCore(maxSlashablePercentageWad);
        vm.stopBroadcast();
        console2.log("sucessfully registered hyperlaneDSS with core");
    }

    function deploy(string memory network) external {
        loadConfig(network);
        deployProxyAdmin();
        deployHyperlaneDSSAsTransparentProxy();
        initializeHyperlaneDSS(network);
        registerHyperlaneDSS();
    }
}
