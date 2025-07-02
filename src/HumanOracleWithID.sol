
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IKycRegistry { function balanceOf(address) external view returns (uint256); }

contract HumanOracleWithID {
    struct Question {
        string  text;
        uint256 yesVotes;
        uint256 noVotes;
        bool    resolved;
        bool    result;
        mapping(address => bool) hasVoted;
    }

    IKycRegistry public immutable kyc;
    uint256 public votingWindow = 3 days;
    uint256 public totalQuestions;
    mapping(uint256 => Question) public questions;
    mapping(uint256 => uint256) public createdAt;

    event QuestionCreated(uint256 id, string text);
    event Voted(uint256 id, address voter, bool choice);
    event Resolved(uint256 id, bool result);

    constructor(address kycRegistry) { kyc = IKycRegistry(kycRegistry); }

    modifier onlyVerified() {
        require(kyc.balanceOf(msg.sender) == 1, "SBT required");
        _;
    }

    function createQuestion(string calldata txt)
        external onlyVerified returns (uint256 id)
    {
        id = totalQuestions++;
        Question storage q = questions[id];
        q.text = txt;
        createdAt[id] = block.timestamp;
        emit QuestionCreated(id, txt);
    }

    function vote(uint256 id, bool choice) external onlyVerified {
        Question storage q = questions[id];
        require(!q.resolved, "resolved");
        require(!q.hasVoted[msg.sender], "already voted");

        q.hasVoted[msg.sender] = true;
        if (choice) q.yesVotes++; else q.noVotes++;
        emit Voted(id, msg.sender, choice);
    }

    function resolve(uint256 id) external {
        Question storage q = questions[id];
        require(!q.resolved, "resolved");
        require(block.timestamp >= createdAt[id] + votingWindow, "too soon");

        q.resolved = true;
        q.result   = q.yesVotes >= q.noVotes;
        emit Resolved(id, q.result);
    }

    function viewQuestion(uint256 id) external view returns(
        string memory text,uint256 yes,uint256 no,bool resolved,bool result
    ){
        Question storage q = questions[id];
        return (q.text,q.yesVotes,q.noVotes,q.resolved,q.result);
    }
}

