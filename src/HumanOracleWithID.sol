
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVotingRecord} from "./interfaces/IVotingRecord.sol";
import {IReputation} from "./interfaces/IReputation.sol";

interface IKycRegistry { function balanceOf(address) external view returns (uint256); }

contract HumanOracleWithID {
    enum QuestionState {
        OPEN,
        VERIFYING,
        CLOSED
    }
    struct Question {
        uint256 createdAt;
        uint256[] records;
        mapping(uint256 => uint256) weighedVotes;
        uint256[] mostVoted;
        uint256 finalResult;
        address[] usersVoted;
        mapping(address => uint256) voted;
        QuestionState resolved;
    }

    IKycRegistry public immutable kyc;
    IKycRegistry public immutable kycJury;
    IVotingRecord public immutable votingRecord;
    IReputation public immutable reputation;
    
    uint256 public votingWindow = 3 days;
    uint256 public totalQuestions;
    Question[] private questions;

    event QuestionCreated(uint256 id, uint256 recordId);
    event Voted();
    event Resolved(uint256 id);
    event InitVerification(uint256 id);

    constructor(address kycRegistry, address kycJuryRegistry, address _votingRecord, address _reputation) {
        kyc = IKycRegistry(kycRegistry);
        kycJury = IKycRegistry(kycJuryRegistry);
        votingRecord = IVotingRecord(_votingRecord);
        reputation = IReputation(_reputation);
    }

    modifier onlyVerified() {
        require(kyc.balanceOf(msg.sender) == 1 || kycJury.balanceOf(msg.sender) == 1, "SBT required");
        _;
    }

    modifier onlyJury() {
        require(kycJury.balanceOf(msg.sender) == 1, "SBT required");
        _;
    }

    modifier onlyInState(uint256 id, QuestionState state) {
        require(questions[id].resolved == state, "Bad question state");
        _;
    }

    function createQuestion(string memory record)
        external
        onlyVerified
        returns (uint256 id, uint256 recordId)
    {
        recordId = votingRecord.safeMint(msg.sender, record);

        Question storage q = questions.push();
        q.records.push(recordId);
        q.weighedVotes[recordId] = reputation.getReputationOf(msg.sender);
        q.usersVoted.push(msg.sender);
        q.voted[msg.sender] = recordId;
        q.createdAt = block.timestamp;
        emit QuestionCreated(id, recordId);
        id = totalQuestions++;
    }

    function vote(uint256 id, uint256 choice, string memory record) external onlyVerified onlyInState(id, QuestionState.OPEN) {
        Question storage q = questions[id];
        require(q.voted[msg.sender] == 0, "already voted");

        if(bytes(record).length > 0) {
            uint256 recordId = votingRecord.safeMint(msg.sender, record);
            q.records.push(recordId);
            q.voted[msg.sender] = recordId;
            q.usersVoted.push(msg.sender);
            q.weighedVotes[recordId] = reputation.getReputationOf(msg.sender);
        } else if(q.weighedVotes[choice] > 0) {
            q.usersVoted.push(msg.sender);
            q.voted[msg.sender] = choice;
            q.weighedVotes[choice] += reputation.getReputationOf(msg.sender);
            emit Voted();
        }
    }

    function resolve(uint256 id) external onlyInState(id, QuestionState.OPEN) {
        Question storage q = questions[id];
        require(block.timestamp >= q.createdAt + votingWindow, "too soon");

        uint256 mostVotes;
        for(uint256 i = 0; i < q.records.length; i++) {
            uint256 votes = q.weighedVotes[q.records[i]];
            if(votes > mostVotes) {
                mostVotes = votes;
            }
        }

        for(uint256 i = 0; i < q.records.length; i++) {
            uint256 recordId = q.records[i];
            if(q.weighedVotes[recordId] == mostVotes) {
                q.mostVoted.push(recordId);
            }
        }

        if(q.mostVoted.length == 1) {
            q.finalResult = q.mostVoted[0];
            _setReputation(id);
            q.resolved = QuestionState.CLOSED;
            emit Resolved(id);
        } else {
            q.resolved = QuestionState.VERIFYING;
            emit InitVerification(id);
        }
    }

    function verifyQuestion(uint256 id, uint256 choice) external onlyJury onlyInState(id, QuestionState.VERIFYING) {
        Question storage q = questions[id];
        if(q.weighedVotes[choice] > 0) {
            q.finalResult = choice;
            _setReputation(id);
            q.resolved = QuestionState.CLOSED;
        }
    }

    function _setReputation(uint256 id) internal {
        Question storage q = questions[id];
        require(q.finalResult != 0, "Not final set");
        for(uint256 i = 0; i < q.usersVoted.length; i++) {
            address user = q.usersVoted[i];
            reputation.updateReputation(user, q.voted[user] == q.finalResult);
        }
    }

    function viewQuestionInfo(uint256 id) external view returns(
        uint256 createdAt, QuestionState resolved, uint256 finalResult
    ){
        Question storage q = questions[id];
        return (q.createdAt, q.resolved, q.finalResult);
    }

    function viewQuestionWeighedVotes(uint256 id, uint256 record) external view returns(uint256) {
        return questions[id].weighedVotes[record];
    }

    function getOptionVoted(uint256 id) external view returns(uint256) {
        return questions[id].voted[msg.sender];
    }

    function viewQuestionResult(uint256 id, uint256 index) external view returns(uint256) {
        return questions[id].mostVoted[index];
    }
}

