// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice A permissionless board whose text is stored only in transaction logs.
contract Docket {
    error BadLength();
    error UnknownIdea();
    error UnknownComment();
    error AlreadyUpvoted();

    event IdeaCreated(uint256 indexed ideaId, address indexed author, string title, string body);
    event CommentPosted(uint256 indexed ideaId, uint256 indexed commentId, address indexed author, string body);
    event Upvoted(uint256 indexed ideaId, uint256 indexed commentId, address indexed voter);

    uint256 public ideaCount;
    mapping(uint256 ideaId => uint256 count) public commentCount;
    mapping(uint256 ideaId => mapping(uint256 commentId => uint256 count)) public upvotes;
    mapping(bytes32 voteKey => bool voted) private _hasUpvoted;

    /// @notice Publish an idea with a 1-120 byte title and a 1-4000 byte body.
    function createIdea(string calldata title, string calldata body) external returns (uint256 ideaId) {
        if (bytes(title).length == 0 || bytes(title).length > 120) revert BadLength();
        if (bytes(body).length == 0 || bytes(body).length > 4000) revert BadLength();
        ideaId = ++ideaCount;
        emit IdeaCreated(ideaId, msg.sender, title, body);
    }

    /// @notice Publish a 1-2000 byte comment on an existing idea.
    function comment(uint256 ideaId, string calldata body) external returns (uint256 commentId) {
        if (ideaId == 0 || ideaId > ideaCount) revert UnknownIdea();
        if (bytes(body).length == 0 || bytes(body).length > 2000) revert BadLength();
        commentId = ++commentCount[ideaId];
        emit CommentPosted(ideaId, commentId, msg.sender, body);
    }

    /// @notice Upvote an idea (commentId zero) or one of its existing comments once per caller.
    function upvote(uint256 ideaId, uint256 commentId) external {
        // A positive comment count already proves its idea exists. Avoid a second cold read
        // on successful comment votes; still distinguish unknown ideas from unknown comments.
        if (commentId == 0) {
            if (ideaId == 0 || ideaId > ideaCount) revert UnknownIdea();
        } else if (commentId > commentCount[ideaId]) {
            if (ideaId == 0 || ideaId > ideaCount) revert UnknownIdea();
            revert UnknownComment();
        }
        bytes32 key = keccak256(abi.encode(ideaId, commentId, msg.sender));
        if (_hasUpvoted[key]) revert AlreadyUpvoted();
        _hasUpvoted[key] = true;
        ++upvotes[ideaId][commentId];
        emit Upvoted(ideaId, commentId, msg.sender);
    }

    /// @notice Whether voter already upvoted this target; false for nonexistent targets.
    function hasUpvoted(uint256 ideaId, uint256 commentId, address voter) external view returns (bool) {
        return _hasUpvoted[keccak256(abi.encode(ideaId, commentId, voter))];
    }
}
