// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deploy} from "../script/Deploy.s.sol";
import {Docket} from "../src/Docket.sol";
import {TestBase} from "./helpers/TestBase.sol";

contract DeployTest is TestBase {
    function testDeployFromExplicitConfiguration() public {
        Deploy script = new Deploy();
        Docket docket = script.deploy(1); // Synthetic test key; no RPC or real wallet.
        assert(address(docket).code.length > 0);
        assert(docket.ideaCount() == 0);
        docket.createIdea("t", "b");
        docket.upvote(1, 0);
        assert(docket.upvotes(1, 0) == 1);
    }

    function testVerificationCommandsUseExactAddressAndChain() public {
        Deploy script = new Deploy();
        string memory suffix =
            " --verifier etherscan --verifier-url https://api.etherscan.io/v2/api --etherscan-api-key \"$ETHERSCAN_API_KEY\" --watch 0x000000000000000000000000000000000000bEEF src/Docket.sol:Docket --compiler-version v0.8.26+commit.8a97fa7a --num-of-optimizations 200 --evm-version cancun";
        assert(
            same(
                script.verificationCommand(address(0xBEEF), 1), string.concat("forge verify-contract --chain 1", suffix)
            )
        );
        assert(
            same(
                script.verificationCommand(address(0xBEEF), 8453),
                string.concat("forge verify-contract --chain 8453", suffix)
            )
        );
    }
}
