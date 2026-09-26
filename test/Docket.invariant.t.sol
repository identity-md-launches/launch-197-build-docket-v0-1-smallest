// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Docket} from "../src/Docket.sol";
import {TestBase, Vm} from "./helpers/TestBase.sol";

/// @dev Independent model is built from decoded logs, not copied from contract returns.
contract DocketHandler is TestBase {
    Docket public immutable docket;
    uint256 public modelIdeas;
    mapping(uint256 => uint256) public modelComments;
    mapping(uint256 => mapping(uint256 => uint256)) public modelVotes;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public modelHasVoted;

    struct Vote {
        uint256 ideaId;
        uint256 commentId;
        address voter;
    }

    Vote[] private votes;

    constructor(Docket target) {
        docket = target;
    }

    function create(uint256 seed, address caller) external {
        string memory title = filled(1 + seed % 120);
        string memory body = filled(1 + seed % 4000);
        uint256 beforeCount = docket.ideaCount();
        vm.recordLogs();
        vm.prank(caller);
        uint256 result = docket.createIdea(title, body);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assert(logs.length == 1 && logs[0].emitter == address(docket));
        assert(logs[0].topics.length == 3);
        assert(logs[0].topics[0] == keccak256("IdeaCreated(uint256,address,string,string)"));
        uint256 loggedId = uint256(logs[0].topics[1]);
        assert(loggedId == modelIdeas + 1 && loggedId == result);
        assert(logs[0].topics[2] == bytes32(uint256(uint160(caller))));
        (string memory loggedTitle, string memory loggedBody) = abi.decode(logs[0].data, (string, string));
        assert(same(title, loggedTitle) && same(body, loggedBody));
        modelIdeas = loggedId;
        assert(docket.ideaCount() == beforeCount + 1);
        _checkAllCounters();
    }

    function post(uint256 seed, uint256 bodySeed, address caller) external {
        if (modelIdeas == 0) return;
        uint256 ideaId = 1 + seed % modelIdeas;
        string memory body = filled(1 + bodySeed % 2000);
        uint256 beforeCount = docket.commentCount(ideaId);
        vm.recordLogs();
        vm.prank(caller);
        uint256 result = docket.comment(ideaId, body);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assert(logs.length == 1 && logs[0].emitter == address(docket));
        assert(logs[0].topics.length == 4);
        assert(logs[0].topics[0] == keccak256("CommentPosted(uint256,uint256,address,string)"));
        assert(uint256(logs[0].topics[1]) == ideaId);
        uint256 loggedId = uint256(logs[0].topics[2]);
        assert(loggedId == modelComments[ideaId] + 1 && loggedId == result);
        assert(logs[0].topics[3] == bytes32(uint256(uint160(caller))));
        assert(same(abi.decode(logs[0].data, (string)), body));
        modelComments[ideaId] = loggedId;
        assert(docket.commentCount(ideaId) == beforeCount + 1);
        _checkAllCounters();
    }

    function reject(uint256 seed, address caller) external {
        uint256 kind = seed % 6;
        bytes memory data;
        bytes4 expected;
        if (kind == 0) {
            data = abi.encodeCall(Docket.createIdea, ("", "b"));
            expected = Docket.BadLength.selector;
        } else if (kind == 1) {
            data = abi.encodeCall(Docket.createIdea, ("t", filled(4001)));
            expected = Docket.BadLength.selector;
        } else if (kind == 2 || modelIdeas == 0) {
            data = abi.encodeCall(Docket.comment, (modelIdeas + 1, "b"));
            expected = Docket.UnknownIdea.selector;
        } else if (kind == 3) {
            data = abi.encodeCall(Docket.comment, (1 + seed % modelIdeas, filled(2001)));
            expected = Docket.BadLength.selector;
        } else if (kind == 4) {
            data = abi.encodeCall(Docket.upvote, (modelIdeas + 1, seed));
            expected = Docket.UnknownIdea.selector;
        } else {
            uint256 ideaId = 1 + seed % modelIdeas;
            data = abi.encodeCall(Docket.upvote, (ideaId, modelComments[ideaId] + 1));
            expected = Docket.UnknownComment.selector;
        }
        vm.recordLogs();
        vm.prank(caller);
        (bool ok, bytes memory reason) = address(docket).call(data);
        assert(!ok && keccak256(reason) == keccak256(abi.encodeWithSelector(expected)));
        assert(vm.getRecordedLogs().length == 0);
        _checkAllCounters();
    }

    function vote(uint256 ideaSeed, uint256 commentSeed, address caller) external {
        if (modelIdeas == 0) return;
        uint256 ideaId = 1 + ideaSeed % modelIdeas;
        uint256 commentId = commentSeed % (modelComments[ideaId] + 1);
        uint256 beforeCount = docket.upvotes(ideaId, commentId);
        vm.recordLogs();
        vm.prank(caller);
        (bool ok, bytes memory reason) = address(docket).call(abi.encodeCall(Docket.upvote, (ideaId, commentId)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        if (modelHasVoted[ideaId][commentId][caller]) {
            assert(!ok && keccak256(reason) == keccak256(abi.encodeWithSelector(Docket.AlreadyUpvoted.selector)));
            assert(logs.length == 0);
        } else {
            assert(ok && reason.length == 0 && logs.length == 1);
            assert(logs[0].emitter == address(docket) && logs[0].topics.length == 4 && logs[0].data.length == 0);
            assert(logs[0].topics[0] == keccak256("Upvoted(uint256,uint256,address)"));
            uint256 loggedIdea = uint256(logs[0].topics[1]);
            uint256 loggedComment = uint256(logs[0].topics[2]);
            address loggedVoter = address(uint160(uint256(logs[0].topics[3])));
            assert(loggedIdea == ideaId && loggedComment == commentId);
            assert(logs[0].topics[3] == bytes32(uint256(uint160(caller))));
            ++modelVotes[loggedIdea][loggedComment];
            modelHasVoted[loggedIdea][loggedComment][loggedVoter] = true;
            votes.push(Vote(loggedIdea, loggedComment, loggedVoter));
            assert(docket.upvotes(ideaId, commentId) == beforeCount + 1);
        }
        // Every successful first vote, and every previously seen vote, must now reject.
        vm.recordLogs();
        vm.prank(caller);
        (ok, reason) = address(docket).call(abi.encodeCall(Docket.upvote, (ideaId, commentId)));
        assert(!ok && keccak256(reason) == keccak256(abi.encodeWithSelector(Docket.AlreadyUpvoted.selector)));
        assert(vm.getRecordedLogs().length == 0);
        _checkAllCounters();
    }

    function checkAllCounters() external view {
        _checkAllCounters();
    }

    function _checkAllCounters() private view {
        assert(docket.ideaCount() == modelIdeas);
        assert(docket.commentCount(0) == 0);
        for (uint256 i = 1; i <= modelIdeas; ++i) {
            assert(docket.commentCount(i) == modelComments[i]);
            for (uint256 j; j <= modelComments[i] + 1; ++j) {
                assert(docket.upvotes(i, j) == modelVotes[i][j]);
            }
        }
        assert(docket.commentCount(modelIdeas + 1) == 0);
        assert(docket.upvotes(modelIdeas + 1, 0) == 0 && docket.upvotes(0, 0) == 0);
        for (uint256 i; i < votes.length; ++i) {
            Vote memory v = votes[i];
            assert(docket.hasUpvoted(v.ideaId, v.commentId, v.voter));
        }
    }
}

contract DocketInvariantTest is TestBase {
    Docket private docket;
    DocketHandler private handler;

    function setUp() public {
        docket = new Docket();
        handler = new DocketHandler(docket);
    }

    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function invariantCountersEqualReconstructedLogs() public view {
        handler.checkAllCounters();
        uint256 count = handler.modelIdeas();
        assert(docket.ideaCount() == count);
        for (uint256 i; i <= count; ++i) {
            assert(docket.commentCount(i) == handler.modelComments(i));
        }
        assert(docket.commentCount(count + 1) == 0);
    }
}
