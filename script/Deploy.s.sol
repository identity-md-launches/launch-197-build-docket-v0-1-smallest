// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Docket} from "../src/Docket.sol";

interface DeployVm {
    function envString(string calldata name) external view returns (string memory);
    function envUint(string calldata name) external view returns (uint256);
    function createSelectFork(string calldata url) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
    function toString(address value) external pure returns (string memory);
    function toString(uint256 value) external pure returns (string memory);
}

/// @notice Run with RPC_URL and PRIVATE_KEY; the contract has no deployment parameters.
contract Deploy {
    DeployVm private constant vm = DeployVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant CONSOLE = address(0x000000000000000000636F6e736F6c652e6c6f67);

    function run() external returns (Docket docket) {
        string memory rpcUrl = vm.envString("RPC_URL");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork(rpcUrl);
        return deploy(privateKey);
    }

    /// @dev Explicit configuration entry point so tests never mutate process environment.
    function deploy(uint256 privateKey) public returns (Docket docket) {
        vm.startBroadcast(privateKey);
        docket = new Docket();
        vm.stopBroadcast();
        _log(string.concat("DOCKET deployed: ", vm.toString(address(docket))));
        _log(string.concat("Chain ID: ", vm.toString(block.chainid)));
        _log(verificationCommand(address(docket), block.chainid));
    }

    /// @dev Etherscan V2 handles both Etherscan and Basescan with one API key.
    function verificationCommand(address deployed, uint256 chainId) public pure returns (string memory) {
        return string.concat(
            "forge verify-contract --chain ",
            vm.toString(chainId),
            " --verifier etherscan --verifier-url https://api.etherscan.io/v2/api --etherscan-api-key \"$ETHERSCAN_API_KEY\" --watch ",
            vm.toString(deployed),
            " src/Docket.sol:Docket --compiler-version v0.8.26+commit.8a97fa7a --num-of-optimizations 200 --evm-version cancun"
        );
    }

    function _log(string memory message) private view {
        (bool success,) = CONSOLE.staticcall(abi.encodeWithSignature("log(string)", message));
        // Foundry intercepts the console address; logging never affects deployment.
        success;
    }
}
