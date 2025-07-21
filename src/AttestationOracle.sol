
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IAttestationRecord} from "./interfaces/IAttestationRecord.sol";
import {IReputation} from "./interfaces/IReputation.sol";

contract AttestationOracle is AccessControl {
    bytes32 public constant USER_ROLE = keccak256("USER");
    bytes32 public constant JURY_ROLE = keccak256("JURY");
    bytes32 public constant AUTHORITY_ROLE = keccak256("AUTHORITY");

    enum AttestationState {
        OPEN,
        VERIFYING,
        OBSERVED,
        CLOSED
    }

    struct AttestationChoice {
        uint256 record;
        bool choice;
    }

    struct Attestation {
        uint256 createdAt;
        uint256[] records;
        mapping(uint256 => int256) weighedAttestations;         //attestation of users for record
        mapping(uint256 => int256) juryWeighedAttestations;     //attestation of juries for record
        uint256 mostAttested;                                   //record most attested by users
        uint256 mostJuryAttested;                               //record most attested by juries
        uint256 finalResult;                                    //record selected as real on resolve attestation
        address[] usersAttested;                                //array of users attested (not public)
        address[] juriesAttested;                               //array of juries attested (not public)
        mapping(address => AttestationChoice) attested;         //attestation of each user/jury (not public)
        AttestationState resolved;                              //state of attestation
    }

    IAttestationRecord public immutable attestationRecord;
    IReputation public immutable reputation;
    
    uint256 public attestationWindow = 2 hours;
    uint256 public totalAttestations;
    Attestation[] private attestations;

    event RegisterRequested(address user, string uri);
    event AttestationCreated(uint256 id, uint256 recordId);
    event Attested();
    event Resolved(uint256 id, AttestationState closeState);
    event InitVerification(uint256 id);

    constructor(
        address defaultAdmin,
        address _attestationRecord,
        address _reputation
    ) {
        attestationRecord = IAttestationRecord(_attestationRecord);
        reputation = IReputation(_reputation);
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    modifier onlyVerified() {
        require(hasRole(USER_ROLE, msg.sender) || hasRole(JURY_ROLE, msg.sender), "Unauthorized");
        _;
    }

    modifier onlyInState(uint256 id, AttestationState state) {
        require(attestations[id].resolved == state, "Bad attestation state");
        _;
    }

    //External call by user to init register
    function requestRegister(string memory uri) external {
        if(!hasRole(USER_ROLE, msg.sender) && !hasRole(JURY_ROLE, msg.sender)) {
            emit RegisterRequested(msg.sender, uri);
        }
    }

    //Private call to finish user registering and init reputation
    function register(address user, bool jury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(jury ? JURY_ROLE:USER_ROLE, user);
        reputation.initReputationOf(user);
    }

    /**
     * execute a sequence of transactions
     * @param uri a string of IPFS json containing record image and data
     */
    function createAttestation(string memory uri)
        external
        onlyVerified
        returns (uint256 id, uint256 recordId)
    {
        //mint new NFT for record
        recordId = attestationRecord.safeMint(msg.sender, uri);

        //init new attestation
        Attestation storage q = attestations.push();
        q.records.push(recordId);
        q.attested[msg.sender] = AttestationChoice(recordId, true);
        q.createdAt = block.timestamp;

        //add record with user vote
        if(hasRole(USER_ROLE, msg.sender)) {
            q.usersAttested.push(msg.sender);
            q.weighedAttestations[recordId] = int256(reputation.getReputationOf(msg.sender));
        }else{
            q.juriesAttested.push(msg.sender);
            q.juryWeighedAttestations[recordId] = int256(reputation.getReputationOf(msg.sender));
        }
        emit AttestationCreated(id, recordId);
        id = totalAttestations++;
    }

    /**
     * Participate on existing attestation, setting as real or fake an uploaded record or uploading a new record
     * @param id index of attestation
     * @param record record chosen
     * @param choice attest selected record as real or fake
     * @param uri IPFS json of new record to attest as real, if uploaded, record and choice are ignored
     */
    function attest(uint256 id, uint256 record, bool choice, string memory uri) external onlyVerified onlyInState(id, AttestationState.OPEN) {
        Attestation storage q = attestations[id];
        require(q.attested[msg.sender].record == 0, "already attested");

        bool isJury = hasRole(JURY_ROLE, msg.sender);

        //add new record if uri is uploaded
        if(bytes(uri).length > 0) {
            uint256 recordId = attestationRecord.safeMint(msg.sender, uri);
            q.records.push(recordId);
            q.attested[msg.sender] = AttestationChoice(recordId, true);
            if(!isJury) {
                q.usersAttested.push(msg.sender);
                q.weighedAttestations[recordId] = int256(reputation.getReputationOf(msg.sender));
            }else{
                q.juriesAttested.push(msg.sender);
                q.juryWeighedAttestations[recordId] = int256(reputation.getReputationOf(msg.sender));
            }
            emit Attested();
        //check that record exists and register user choice
        } else if (q.weighedAttestations[record] > 0 || q.juryWeighedAttestations[record] > 0) {
            if(!isJury) {
                q.usersAttested.push(msg.sender);
                if(choice) {
                    q.weighedAttestations[record] += int256(reputation.getReputationOf(msg.sender));
                }else {
                    q.weighedAttestations[record] -= int256(reputation.getReputationOf(msg.sender));
                }
            }else{
                q.juriesAttested.push(msg.sender);
                if(choice) {
                    q.juryWeighedAttestations[record] += int256(reputation.getReputationOf(msg.sender));
                }else {
                    q.juryWeighedAttestations[record] -= int256(reputation.getReputationOf(msg.sender));
                }
            }
            q.attested[msg.sender] = AttestationChoice(record, choice);
            emit Attested();
        }
    }

    /**
     * Resolve an attestation after time defined on attestationWindow
     * @param id index of attestation
     */
    function resolve(uint256 id) external onlyInState(id, AttestationState.OPEN) {
        Attestation storage q = attestations[id];
        require(block.timestamp >= q.createdAt + attestationWindow, "too soon");

        //Check unanimity if only one record is uploaded
        if(q.records.length == 1) {
            _checkUnanimity(id);
            return;
        }

        //Get most attested record by users
        int256 mostAttestations;
        for(uint256 i = 0; i < q.records.length; i++) {
            int256 attestationCount = q.weighedAttestations[q.records[i]];
            if(attestationCount > mostAttestations) {
                mostAttestations = attestationCount;
                q.mostAttested = q.records[i];
            }
        }

        //Get most attested record by juries
        int256 mostJuryAttestations;
        for(uint256 i = 0; i < q.records.length; i++) {
            int256 attestationCount = q.juryWeighedAttestations[q.records[i]];
            if(attestationCount > mostJuryAttestations) {
                mostJuryAttestations = attestationCount;
                q.mostJuryAttested = q.records[i];
            }
        }

        //only users voted
        if(q.mostAttested > 0 && q.mostJuryAttested == 0) {
            q.finalResult = q.mostAttested;
            _setReputation(id);
            q.resolved = AttestationState.OBSERVED;
            emit Resolved(id, q.resolved);
        }
        //only juries voted
        else if(q.mostAttested == 0 && q.mostJuryAttested > 0) {
            q.finalResult = q.mostJuryAttested;
            _setReputation(id);
            q.resolved = AttestationState.OBSERVED;
            emit Resolved(id, q.resolved);
        }
        //most users match most juries
        else if(q.mostAttested == q.mostJuryAttested) {
            q.finalResult = q.mostAttested;
            _setReputation(id);
            q.resolved = AttestationState.OBSERVED;
            emit Resolved(id, q.resolved);
        }
        //most users doesn't match most juries
        else {
            q.resolved = AttestationState.VERIFYING;
            emit InitVerification(id);
        }
    }

    /**
     * Check unanimity, if all users and juries voted unique record as real,
     * attestation is CLOSED, else, is OBSERVED. Also sets users/juries reputation.
     * @param id index of attestation
     */
    function _checkUnanimity(uint256 id) private {
        Attestation storage q = attestations[id];
        q.finalResult = q.records[0];
        q.resolved = AttestationState.CLOSED;
        
        for(uint256 i = 0; i < q.usersAttested.length; i++) {
            address user = q.usersAttested[i];
            reputation.updateReputation(user, q.attested[user].choice);
            if(!q.attested[user].choice && q.resolved == AttestationState.CLOSED) {
                q.resolved = AttestationState.OBSERVED;
            }
        }

        for(uint256 i = 0; i < q.juriesAttested.length; i++) {
            address jury = q.juriesAttested[i];
            reputation.updateReputation(jury, q.attested[jury].choice);
            if(!q.attested[jury].choice && q.resolved == AttestationState.CLOSED) {
                q.resolved = AttestationState.OBSERVED;
            }
        }
    }

    /**
     * Set final result for VERIFYING attestation,
     * only callable by AUTHORITIES
     * @param id index of attestation
     * @param choice record selected as real
     */
    function verifyAttestation(uint256 id, uint256 choice) external onlyRole(AUTHORITY_ROLE) onlyInState(id, AttestationState.VERIFYING) {
        Attestation storage q = attestations[id];
        if(q.weighedAttestations[choice] > 0 || q.juryWeighedAttestations[choice] > 0) {
            q.finalResult = choice;
            _setReputation(id);
            q.resolved = AttestationState.CLOSED;
        }
    }

    /**
     * Update users/juries reputation given an attestation with a final result
     * @param id index of attestation
     */
    function _setReputation(uint256 id) internal {
        Attestation storage q = attestations[id];
        require(q.finalResult != 0, "Not final set");
        for(uint256 i = 0; i < q.usersAttested.length; i++) {
            address user = q.usersAttested[i];
            reputation.updateReputation(user, q.attested[user].record == q.finalResult && q.attested[user].choice);
        }

        for(uint256 i = 0; i < q.juriesAttested.length; i++) {
            address user = q.juriesAttested[i];
            reputation.updateReputation(user, q.attested[user].record == q.finalResult && q.attested[user].choice);
        }
    }

    function getAttestationInfo(uint256 id) external view returns(
        uint256 createdAt, AttestationState resolved, uint256 finalResult
    ){
        Attestation storage q = attestations[id];
        return (q.createdAt, q.resolved, q.finalResult);
    }

    function getWeighedAttestations(uint256 id, uint256 record) external view returns(int256) {
        return attestations[id].weighedAttestations[record];
    }

    function getJuryWeighedAttestations(uint256 id, uint256 record) external view returns(int256) {
        return attestations[id].juryWeighedAttestations[record];
    }

    function getOptionAttested(uint256 id) external view returns(uint256, bool) {
        return (attestations[id].attested[msg.sender].record, attestations[id].attested[msg.sender].choice);
    }

    function viewAttestationResult(uint256 id) external view returns(uint256, uint256) {
        return (attestations[id].mostAttested, attestations[id].mostJuryAttested);
    }
}

