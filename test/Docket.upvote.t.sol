// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Docket} from "../src/Docket.sol";
import {TestBase, GasCaller} from "./helpers/TestBase.sol";

contract RevertingCaller {
    error Rollback();

    function actThenRevert(Docket docket) external {
        docket.createIdea("rolled back", "body");
        docket.comment(1, "rolled back");
        docket.upvote(1, 1);
        revert Rollback();
    }
}

contract DocketUpvoteTest is TestBase {
    Docket private docket;
    event Upvoted(uint256 indexed ideaId, uint256 indexed commentId, address indexed voter);

    function setUp() public {
        docket = new Docket();
        docket.createIdea("one", "b");
        docket.createIdea("two", "b");
        docket.comment(1, "first");
        docket.comment(1, "second");
        docket.comment(2, "first");
    }

    function testFuzzUnknownViews(uint256 ideaId, uint256 commentId, address voter) public view {
        assert(docket.upvotes(ideaId, commentId) == 0);
        assert(!docket.hasUpvoted(ideaId, commentId, voter));
    }

    function testFuzzExactEventsAndTargetIndependence(address voter) public {
        for (uint256 i = 1; i <= 2; ++i) {
            for (uint256 j; j <= docket.commentCount(i); ++j) {
                vm.expectEmit(true, true, true, true, address(docket));
                emit Upvoted(i, j, voter);
                vm.prank(voter);
                docket.upvote(i, j);
                assert(docket.upvotes(i, j) == 1);
                assert(docket.hasUpvoted(i, j, voter));
                vm.expectRevert(Docket.AlreadyUpvoted.selector);
                vm.prank(voter);
                docket.upvote(i, j);
                assert(docket.upvotes(i, j) == 1);
            }
        }
        assert(docket.ideaCount() == 2);
        assert(docket.commentCount(1) == 2 && docket.commentCount(2) == 1);
    }

    function testFuzzDistinctVoters(address a, address b) public {
        vm.prank(a);
        docket.upvote(1, 1);
        if (a == b) vm.expectRevert(Docket.AlreadyUpvoted.selector);
        vm.prank(b);
        docket.upvote(1, 1);
        assert(docket.upvotes(1, 1) == (a == b ? 1 : 2));
        assert(docket.hasUpvoted(1, 1, a) && docket.hasUpvoted(1, 1, b));
        assert(docket.upvotes(1, 0) == 0 && docket.upvotes(2, 1) == 0);
    }

    function testFuzzArbitraryTargets(uint256 ideaId, uint256 commentId, address voter) public {
        bool ideaExists = ideaId == 1 || ideaId == 2;
        bool valid = ideaExists && commentId <= docket.commentCount(ideaId);
        if (!ideaExists) vm.expectRevert(Docket.UnknownIdea.selector);
        else if (!valid) vm.expectRevert(Docket.UnknownComment.selector);
        vm.prank(voter);
        docket.upvote(ideaId, commentId);
        assert(docket.upvotes(ideaId, commentId) == (valid ? 1 : 0));
        assert(docket.hasUpvoted(ideaId, commentId, voter) == valid);
        assert(docket.ideaCount() == 2 && docket.commentCount(1) == 2 && docket.commentCount(2) == 1);
    }

    function testUnknownTargetsAndErrorPrecedence() public {
        Docket empty = new Docket();
        vm.expectRevert(Docket.UnknownIdea.selector);
        empty.upvote(1, 0);
        uint256[3] memory unknown = [uint256(0), uint256(3), type(uint256).max];
        for (uint256 i; i < unknown.length; ++i) {
            vm.expectRevert(Docket.UnknownIdea.selector);
            docket.upvote(unknown[i], 0);
            vm.expectRevert(Docket.UnknownIdea.selector);
            docket.upvote(unknown[i], 1);
        }
        vm.expectRevert(Docket.UnknownComment.selector);
        docket.upvote(1, 3);
        vm.expectRevert(Docket.UnknownComment.selector);
        docket.upvote(1, type(uint256).max);
        vm.expectRevert(Docket.UnknownComment.selector);
        docket.upvote(2, 2); // Comment 2 exists on idea 1 only.
        docket.createIdea("no comments", "b");
        vm.expectRevert(Docket.UnknownComment.selector);
        docket.upvote(3, 1);
        docket.upvote(3, 0);
        assert(docket.upvotes(3, 0) == 1);
    }

    function testRejectedVotesAreAtomicAndCanSucceedAfterTargetCreation() public {
        vm.recordLogs();
        _reject(3, 1, Docket.UnknownIdea.selector);
        _reject(1, 3, Docket.UnknownComment.selector);
        assert(vm.getRecordedLogs().length == 0);
        assert(!docket.hasUpvoted(3, 1, address(this)) && docket.upvotes(3, 1) == 0);
        assert(!docket.hasUpvoted(1, 3, address(this)) && docket.upvotes(1, 3) == 0);
        docket.comment(1, "third");
        docket.upvote(1, 3);
        docket.createIdea("three", "b");
        docket.comment(3, "first");
        docket.upvote(3, 1);
        vm.recordLogs();
        _reject(3, 1, Docket.AlreadyUpvoted.selector);
        assert(vm.getRecordedLogs().length == 0);
        assert(docket.upvotes(3, 1) == 1 && docket.hasUpvoted(3, 1, address(this)));
    }

    function testVoteRecordUsesSpecifiedSingleMappingKey() public {
        docket.upvote(1, 2);
        bytes32 key = keccak256(abi.encode(uint256(1), uint256(2), address(this)));
        // Slots 0/1/2/3: ideaCount, commentCount, upvotes, _hasUpvoted.
        assert(uint256(vm.load(address(docket), keccak256(abi.encode(key, uint256(3))))) == 1);
    }

    function testUpvoteOverflowRollsBackVoteRecordAndLogs() public {
        bytes32 inner = keccak256(abi.encode(uint256(1), uint256(2)));
        bytes32 slot = keccak256(abi.encode(uint256(0), inner));
        vm.store(address(docket), slot, bytes32(type(uint256).max - 1));
        docket.upvote(1, 0);
        assert(docket.upvotes(1, 0) == type(uint256).max);
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        vm.prank(address(0xCAFE));
        docket.upvote(1, 0);
        assert(vm.getRecordedLogs().length == 0);
        assert(docket.upvotes(1, 0) == type(uint256).max);
        assert(!docket.hasUpvoted(1, 0, address(0xCAFE)));
        docket.upvote(1, 1);
        assert(docket.upvotes(1, 1) == 1);
    }

    function testVoteOutOfGasRollsBackBothWrites() public {
        GasCaller caller = new GasCaller();
        // Enough for the vote-record write, insufficient for the second fresh SSTORE.
        (bool ok, bytes memory reason) = caller.forward(address(docket), abi.encodeCall(Docket.upvote, (1, 0)), 35_000);
        assert(!ok && reason.length == 0);
        assert(!docket.hasUpvoted(1, 0, address(caller)) && docket.upvotes(1, 0) == 0);
        docket.upvote(1, 0);
        assert(docket.upvotes(1, 0) == 1);
    }

    function testNoPayableVoteOrMalformedAbi() public {
        vm.deal(address(this), 1);
        vm.recordLogs();
        (bool paid,) = address(docket).call{value: 1}(abi.encodeCall(Docket.upvote, (1, 0)));
        (bool short,) = address(docket).call(abi.encodePacked(Docket.upvote.selector, uint256(1)));
        assert(!paid && !short && vm.getRecordedLogs().length == 0);
        assert(docket.upvotes(1, 0) == 0 && !docket.hasUpvoted(1, 0, address(this)));
        assert(address(docket).balance == 0);
    }

    function testSuccessfulCallsRollBackWhenOuterCallerReverts() public {
        RevertingCaller caller = new RevertingCaller();
        vm.expectRevert(RevertingCaller.Rollback.selector);
        caller.actThenRevert(docket);
        assert(docket.ideaCount() == 2 && docket.commentCount(1) == 2);
        assert(docket.upvotes(1, 1) == 0 && !docket.hasUpvoted(1, 1, address(caller)));
        assert(docket.createIdea("next", "body") == 3);
        assert(docket.comment(1, "next") == 3);
        vm.prank(address(caller));
        docket.upvote(1, 1);
        assert(docket.upvotes(1, 1) == 1);
    }

    function _reject(uint256 ideaId, uint256 commentId, bytes4 expected) private {
        (bool ok, bytes memory reason) = address(docket).call(abi.encodeCall(Docket.upvote, (ideaId, commentId)));
        assert(!ok && keccak256(reason) == keccak256(abi.encodeWithSelector(expected)));
    }
}
