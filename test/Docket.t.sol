// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Docket} from "../src/Docket.sol";
import {TestBase, Vm, GasCaller} from "./helpers/TestBase.sol";

contract DocketTest is TestBase {
    Docket internal docket;

    event IdeaCreated(uint256 indexed ideaId, address indexed author, string title, string body);
    event CommentPosted(uint256 indexed ideaId, uint256 indexed commentId, address indexed author, string body);

    function setUp() public {
        docket = new Docket();
    }

    function testInitialAndUnknownCounters() public view {
        assert(docket.ideaCount() == 0);
        assert(docket.commentCount(0) == 0);
        assert(docket.commentCount(1) == 0);
        assert(docket.commentCount(type(uint256).max) == 0);
    }

    function testExactEventsAndIndependentCommentSequences() public {
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        vm.expectEmit(true, true, false, true, address(docket));
        emit IdeaCreated(1, alice, "A title", "An idea");
        vm.prank(alice);
        assert(docket.createIdea("A title", "An idea") == 1);
        vm.expectEmit(true, true, false, true, address(docket));
        emit IdeaCreated(2, bob, "Second", "Another idea");
        vm.prank(bob);
        assert(docket.createIdea("Second", "Another idea") == 2);

        vm.expectEmit(true, true, true, true, address(docket));
        emit CommentPosted(2, 1, alice, "First on second");
        vm.prank(alice);
        assert(docket.comment(2, "First on second") == 1);
        vm.expectEmit(true, true, true, true, address(docket));
        emit CommentPosted(1, 1, bob, "First on first");
        vm.prank(bob);
        assert(docket.comment(1, "First on first") == 1);
        vm.expectEmit(true, true, true, true, address(docket));
        emit CommentPosted(2, 2, bob, "Second on second");
        vm.prank(bob);
        assert(docket.comment(2, "Second on second") == 2);
        assert(docket.ideaCount() == 2);
        assert(docket.commentCount(1) == 1);
        assert(docket.commentCount(2) == 2);
    }

    function testFuzzTitleBoundaries(uint256 seed, address caller) public {
        _title(0, caller);
        _title(1, caller);
        _title(119, caller);
        _title(120, caller);
        _title(121, caller);
        _title(2 + seed % 117, caller);
        _title(122 + seed % 8192, caller);
    }

    function testFuzzIdeaBodyBoundaries(uint256 seed, address caller) public {
        _ideaBody(0, caller);
        _ideaBody(1, caller);
        _ideaBody(3999, caller);
        _ideaBody(4000, caller);
        _ideaBody(4001, caller);
        _ideaBody(2 + seed % 3997, caller);
        _ideaBody(4002 + seed % 8192, caller);
    }

    function testFuzzCommentBodyBoundaries(uint256 seed, address caller) public {
        docket.createIdea("t", "b");
        _commentBody(0, caller);
        _commentBody(1, caller);
        _commentBody(1999, caller);
        _commentBody(2000, caller);
        _commentBody(2001, caller);
        _commentBody(2 + seed % 1997, caller);
        _commentBody(2002 + seed % 8192, caller);
    }

    function testFuzzArbitraryTextAndCallers(string memory title, string memory body, address caller) public {
        bool valid = bytes(title).length > 0 && bytes(title).length <= 120 && bytes(body).length > 0
            && bytes(body).length <= 4000;
        if (valid) {
            vm.expectEmit(true, true, false, true, address(docket));
            emit IdeaCreated(1, caller, title, body);
        } else {
            vm.expectRevert(Docket.BadLength.selector);
        }
        vm.prank(caller);
        docket.createIdea(title, body);
        assert(docket.ideaCount() == (valid ? 1 : 0));
    }

    function testFuzzArbitraryCommentTextAndCallers(string memory body, address caller) public {
        docket.createIdea("t", "b");
        bool valid = bytes(body).length > 0 && bytes(body).length <= 2000;
        if (valid) {
            vm.expectEmit(true, true, true, true, address(docket));
            emit CommentPosted(1, 1, caller, body);
        } else {
            vm.expectRevert(Docket.BadLength.selector);
        }
        vm.prank(caller);
        docket.comment(1, body);
        assert(docket.ideaCount() == 1);
        assert(docket.commentCount(1) == (valid ? 1 : 0));
    }

    function testFuzzArbitraryIdeaIds(uint256 ideaId, address caller) public {
        docket.createIdea("one", "b");
        docket.createIdea("two", "b");
        if (ideaId == 1 || ideaId == 2) {
            vm.prank(caller);
            assert(docket.comment(ideaId, "b") == 1);
            assert(docket.commentCount(ideaId) == 1);
        } else {
            vm.expectRevert(Docket.UnknownIdea.selector);
            vm.prank(caller);
            docket.comment(ideaId, "b");
            assert(docket.commentCount(ideaId) == 0);
        }
        assert(docket.ideaCount() == 2);
    }

    function testUnknownIdeaBeforeAndAfterCreationAndErrorPrecedence() public {
        vm.expectRevert(Docket.UnknownIdea.selector);
        docket.comment(0, "b");
        vm.expectRevert(Docket.UnknownIdea.selector);
        docket.comment(1, "b");
        docket.createIdea("t", "b");
        vm.expectRevert(Docket.UnknownIdea.selector);
        docket.comment(0, "");
        vm.expectRevert(Docket.UnknownIdea.selector);
        docket.comment(2, "");
        vm.expectRevert(Docket.UnknownIdea.selector);
        docket.comment(type(uint256).max, "b");
        assert(docket.commentCount(0) == 0);
        assert(docket.commentCount(2) == 0);
    }

    function testLengthsCountBytesAndPreserveNulAndInvalidUtf8() public {
        // 60 two-byte characters reach 120 bytes; 61 exceed it.
        bytes memory title = new bytes(120);
        for (uint256 i; i < 120; i += 2) {
            title[i] = 0xc3;
            title[i + 1] = 0xa9;
        }
        assert(docket.createIdea(string(title), unicode"🌱") == 1);
        vm.expectRevert(Docket.BadLength.selector);
        docket.createIdea(string.concat(string(title), unicode"é"), "b");
        // Solidity strings are arbitrary bytes; there is no UTF-8 or markup filter.
        bytes memory raw = hex"00ff3c3e";
        vm.expectEmit(true, true, true, true, address(docket));
        emit CommentPosted(1, 1, address(this), string(raw));
        assert(docket.comment(1, string(raw)) == 1);
    }

    function testRejectedCallsLeaveNoLogsOrState() public {
        docket.createIdea("t", "b");
        docket.comment(1, "existing");
        vm.recordLogs();
        (bool a, bytes memory ra) = address(docket).call(abi.encodeCall(Docket.createIdea, ("", "b")));
        (bool b, bytes memory rb) = address(docket).call(abi.encodeCall(Docket.comment, (1, "")));
        (bool c, bytes memory rc) = address(docket).call(abi.encodeCall(Docket.comment, (2, "b")));
        assert(!a && !b && !c);
        assert(keccak256(ra) == keccak256(abi.encodeWithSelector(Docket.BadLength.selector)));
        assert(keccak256(rb) == keccak256(abi.encodeWithSelector(Docket.BadLength.selector)));
        assert(keccak256(rc) == keccak256(abi.encodeWithSelector(Docket.UnknownIdea.selector)));
        assert(vm.getRecordedLogs().length == 0);
        assert(docket.ideaCount() == 1 && docket.commentCount(1) == 1 && docket.commentCount(2) == 0);
    }

    function testIdeaOverflowIsAtomic() public {
        vm.store(address(docket), bytes32(uint256(0)), bytes32(type(uint256).max - 1));
        vm.expectEmit(true, true, false, true, address(docket));
        emit IdeaCreated(type(uint256).max, address(this), "last", "b");
        assert(docket.createIdea("last", "b") == type(uint256).max);
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        docket.createIdea("overflow", "b");
        assert(docket.ideaCount() == type(uint256).max);
        assert(vm.getRecordedLogs().length == 0);
    }

    function testCommentOverflowIsAtomicAndIsolated() public {
        docket.createIdea("one", "b");
        docket.createIdea("two", "b");
        bytes32 slot = keccak256(abi.encode(uint256(1), uint256(1)));
        vm.store(address(docket), slot, bytes32(type(uint256).max - 1));
        vm.expectEmit(true, true, true, true, address(docket));
        emit CommentPosted(1, type(uint256).max, address(this), "last");
        assert(docket.comment(1, "last") == type(uint256).max);
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        docket.comment(1, "overflow");
        assert(vm.getRecordedLogs().length == 0);
        assert(docket.commentCount(1) == type(uint256).max);
        assert(docket.comment(2, "unaffected") == 1);
        assert(docket.ideaCount() == 2);
    }

    function testNoPayableOrFallbackOrPrivilegedSelectors() public {
        vm.deal(address(this), 3);
        vm.recordLogs();
        (bool a,) = address(docket).call{value: 1}("");
        (bool b,) = address(docket).call{value: 1}(abi.encodeCall(Docket.createIdea, ("t", "b")));
        (bool c,) = address(docket).call{value: 1}(abi.encodeCall(Docket.comment, (1, "b")));
        (bool d,) = address(docket).call(abi.encodeWithSignature("transferOwnership(address)", address(this)));
        (bool e,) = address(docket).call(abi.encodeWithSignature("pause()"));
        (bool f,) = address(docket).call(abi.encodeWithSignature("upgradeTo(address)", address(this)));
        (bool g,) = address(docket).call(abi.encodeWithSignature("initialize()"));
        assert(!a && !b && !c && !d && !e && !f && !g);
        assert(address(docket).balance == 0 && docket.ideaCount() == 0);
        assert(vm.getRecordedLogs().length == 0);
    }

    function testOversizedPayloadsRejectWithinBoundedExecutionGas() public {
        docket.createIdea("t", "b");
        GasCaller caller = new GasCaller();
        string memory oversized = filled(65_536);
        bytes[3] memory payloads = [
            abi.encodeCall(Docket.createIdea, (oversized, "b")),
            abi.encodeCall(Docket.createIdea, ("t", oversized)),
            abi.encodeCall(Docket.comment, (1, oversized))
        ];
        vm.recordLogs();
        for (uint256 i; i < payloads.length; ++i) {
            (bool ok, bytes memory reason) = caller.forward(address(docket), payloads[i], 10_000);
            assert(!ok && keccak256(reason) == keccak256(abi.encodeWithSelector(Docket.BadLength.selector)));
        }
        assert(vm.getRecordedLogs().length == 0);
        assert(docket.ideaCount() == 1 && docket.commentCount(1) == 0);
    }

    function testCommentFloodPreservesOtherIdeasAndContinuedPosting() public {
        docket.createIdea("target", "b");
        docket.createIdea("other", "b");
        for (uint256 i = 1; i <= 256; ++i) {
            vm.prank(address(0xBAD));
            assert(docket.comment(1, "spam") == i);
        }
        assert(docket.ideaCount() == 2 && docket.commentCount(1) == 256);
        assert(docket.commentCount(2) == 0);
        assert(docket.comment(2, "independent") == 1);
        assert(docket.comment(1, "still usable") == 257);
    }

    function testMalformedAbiRejectsWithoutStateOrLogs() public {
        docket.createIdea("t", "b");
        bytes[4] memory payloads = [
            abi.encodePacked(Docket.createIdea.selector),
            abi.encodePacked(Docket.comment.selector),
            abi.encodePacked(
                Docket.createIdea.selector, abi.encode(uint256(64), uint256(96), type(uint256).max, uint256(1))
            ),
            abi.encodePacked(Docket.comment.selector, abi.encode(uint256(1), uint256(64), uint256(4)))
        ];
        vm.recordLogs();
        for (uint256 i; i < payloads.length; ++i) {
            (bool ok,) = address(docket).call(payloads[i]);
            assert(!ok);
        }
        assert(vm.getRecordedLogs().length == 0);
        assert(docket.ideaCount() == 1 && docket.commentCount(1) == 0);
    }

    function testOutOfGasDuringEventEncodingRollsBackCounters() public {
        GasCaller caller = new GasCaller();
        bytes memory ideaData = abi.encodeCall(Docket.createIdea, (filled(120), filled(4000)));
        bytes memory commentData = abi.encodeCall(Docket.comment, (1, filled(2000)));
        vm.recordLogs();
        (bool ideaOk, bytes memory ideaReason) = caller.forward(address(docket), ideaData, 28_000);
        assert(!ideaOk && ideaReason.length == 0);
        assert(docket.ideaCount() == 0 && vm.getRecordedLogs().length == 0);
        assert(docket.createIdea("first", "b") == 1);
        vm.recordLogs();
        (bool commentOk, bytes memory commentReason) = caller.forward(address(docket), commentData, 28_000);
        assert(!commentOk && commentReason.length == 0);
        assert(docket.commentCount(1) == 0 && vm.getRecordedLogs().length == 0);
        assert(docket.comment(1, "first") == 1);
    }

    function testSameRuntimeOnMainnetAndBase() public {
        uint256 previous = block.chainid;
        vm.chainId(1);
        Docket mainnet = new Docket();
        vm.chainId(8453);
        Docket base = new Docket();
        assert(address(mainnet).codehash == address(base).codehash);
        assert(mainnet.createIdea("t", "b") == base.createIdea("t", "b"));
        vm.chainId(previous);
    }

    function _title(uint256 length, address caller) private {
        string memory title = filled(length);
        uint256 beforeCount = docket.ideaCount();
        bool valid = length > 0 && length <= 120;
        if (!valid) vm.expectRevert(Docket.BadLength.selector);
        vm.prank(caller);
        docket.createIdea(title, "b");
        assert(docket.ideaCount() == beforeCount + (valid ? 1 : 0));
    }

    function _ideaBody(uint256 length, address caller) private {
        string memory body = filled(length);
        uint256 beforeCount = docket.ideaCount();
        bool valid = length > 0 && length <= 4000;
        if (!valid) vm.expectRevert(Docket.BadLength.selector);
        vm.prank(caller);
        docket.createIdea("t", body);
        assert(docket.ideaCount() == beforeCount + (valid ? 1 : 0));
    }

    function _commentBody(uint256 length, address caller) private {
        string memory body = filled(length);
        uint256 beforeCount = docket.commentCount(1);
        bool valid = length > 0 && length <= 2000;
        if (!valid) vm.expectRevert(Docket.BadLength.selector);
        vm.prank(caller);
        docket.comment(1, body);
        assert(docket.ideaCount() == 1);
        assert(docket.commentCount(1) == beforeCount + (valid ? 1 : 0));
    }
}
