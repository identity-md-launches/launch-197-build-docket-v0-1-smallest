// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Only the Foundry cheatcodes used by this project; no downloaded test dependencies.
interface Vm {
    struct Gas {
        uint64 gasLimit;
        uint64 gasTotalUsed;
        uint64 gasMemoryUsed;
        int64 gasRefunded;
        uint64 gasRemaining;
    }

    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function pauseGasMetering() external;
    function resumeGasMetering() external;
    function prank(address sender) external;
    function expectRevert(bytes4 revertData) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function store(address target, bytes32 slot, bytes32 value) external;
    function deal(address account, uint256 balance) external;
    function chainId(uint256 newChainId) external;
    function lastCallGas() external view returns (Gas memory);
    function load(address target, bytes32 slot) external view returns (bytes32);
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function filled(uint256 length) internal pure returns (string memory) {
        bytes memory data = new bytes(length);
        for (uint256 i; i < length; ++i) {
            data[i] = "x";
        }
        return string(data);
    }

    function same(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

/// @dev Nested EVM call keeps the forwarded gas an execution budget even under --isolate.
contract GasCaller {
    function forward(address target, bytes calldata data, uint256 gasLimit)
        external
        returns (bool ok, bytes memory result)
    {
        return target.call{gas: gasLimit}(data);
    }
}
