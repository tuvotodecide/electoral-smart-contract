
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAttestationRecord} from "./interfaces/IAttestationRecord.sol";
import {IReputation} from "./interfaces/IReputation.sol";
import {IWiraToken} from "./interfaces/IWiraToken.sol";

contract AttestationOracle is AccessControl {
    using SafeERC20 for IWiraToken;

    bytes32 public constant USER_ROLE = keccak256("USER");
    bytes32 public constant JURY_ROLE = keccak256("JURY");
    bytes32 public constant AUTHORITY_ROLE = keccak256("AUTHORITY");

    uint256 public attestStart;
    uint256 public attestEnd;

    enum AttestationState {
        OPEN,
        CONSENSUAL,
        VERIFYING,
        CLOSED
    }

    struct AttestationChoice {
        uint256 record;
        bool choice;
    }

    struct RecordAttestation {
        uint256 yesCount;
        uint256 noesCount;
        int256 weighedAttestation;
    }

    struct Attestation {
        uint256[] records;
        uint256 cumulatedStake;                                         //cumulated stake to redistrubute
        mapping(uint256 => RecordAttestation) userAttestations;        //attestation of users for record
        mapping(uint256 => RecordAttestation) juryAttestations;         //attestation of juries for record
        uint256 mostAttested;                                           //record most attested by users
        uint256 mostJuryAttested;                                       //record most attested by juries
        uint256 finalResult;                                            //record selected as real on resolve attestation
        address[] usersAttested;                                        //array of users attested (not public)
        address[] juriesAttested;                                       //array of juries attested (not public)
        mapping(address => AttestationChoice) attested;                 //attestation of each user/jury (not public)
        AttestationState resolved;                                      //state of attestation
    }

    IAttestationRecord public immutable attestationRecord;
    IReputation public immutable reputation;
    IWiraToken public immutable stakeToken;
    uint256 public stake;
    uint256 public attestationWindow = 2 hours;
    uint256 public totalAttestations;
    Attestation[] private attestations;

    event RegisterRequested(address user, string uri);
    event AttestationCreated(uint256 id, uint256 recordId);
    event Attested(uint256 recordId);
    event Resolved(uint256 id, AttestationState closeState);
    event InitVerification(uint256 id);

    constructor(
        address defaultAdmin,
        address _attestationRecord,
        address _reputation,
        address _stakeToken,
        uint256 _stake
    ) {
        attestationRecord = IAttestationRecord(_attestationRecord);
        reputation = IReputation(_reputation);
        stakeToken = IWiraToken(_stakeToken);
        stake = _stake;
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    modifier onlyActive() {
        require(block.timestamp > attestStart && block.timestamp < attestEnd, "Oracle inactive");
        _;
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
    function requestRegister(string memory uri) external onlyActive {
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
     * make a stake deposit of an attestation to redistribute on resolve
     */
    function _depositStake(uint256 id) private {
        stakeToken.mint(address(this), stake);
        attestations[id].cumulatedStake += stake;
    }

    /**
     * execute a sequence of transactions
     * @param uri a string of IPFS json containing record image and data
     */
    function createAttestation(string memory uri)
        external
        onlyVerified
        onlyActive
        returns (uint256 id, uint256 recordId)
    {
        //mint new NFT for record
        recordId = attestationRecord.safeMint(msg.sender, uri);

        //init new attestation
        Attestation storage q = attestations.push();
        q.records.push(recordId);
        q.attested[msg.sender] = AttestationChoice(recordId, true);

        //add record with user vote
        if(hasRole(USER_ROLE, msg.sender)) {
            q.usersAttested.push(msg.sender);
            q.userAttestations[recordId] = RecordAttestation(1, 0, int256(reputation.getReputationOf(msg.sender)));
        }else{
            q.juriesAttested.push(msg.sender);
            q.juryAttestations[recordId] = RecordAttestation(1, 0, int256(reputation.getReputationOf(msg.sender)));
        }
        id = totalAttestations++;

        //deposit first stake
        _depositStake(id);
        emit AttestationCreated(id, recordId);
    }

    /**
     * Participate on existing attestation, setting as real or fake an uploaded record or uploading a new record
     * @param id index of attestation
     * @param record record chosen
     * @param choice attest selected record as real or fake
     * @param uri IPFS json of new record to attest as real, if uploaded, record and choice are ignored
     */
    function attest(uint256 id, uint256 record, bool choice, string memory uri) external onlyVerified onlyActive onlyInState(id, AttestationState.OPEN) returns(uint256) {
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
                q.userAttestations[recordId] = RecordAttestation(1, 0, int256(reputation.getReputationOf(msg.sender)));
            }else{
                q.juriesAttested.push(msg.sender);
                q.juryAttestations[recordId] = RecordAttestation(1, 0, int256(reputation.getReputationOf(msg.sender)));
            }
            _depositStake(id);
            emit Attested(recordId);
            return recordId;
        //check that record exists and register user choice
        } else if (q.userAttestations[record].yesCount > 0 || q.juryAttestations[record].yesCount > 0) {
            if(!isJury) {
                q.usersAttested.push(msg.sender);
                if(choice) {
                    q.userAttestations[record].yesCount ++;
                    q.userAttestations[record].weighedAttestation += int256(reputation.getReputationOf(msg.sender));
                }else {
                    q.userAttestations[record].noesCount ++;
                    q.userAttestations[record].weighedAttestation -= int256(reputation.getReputationOf(msg.sender));
                }
            }else{
                q.juriesAttested.push(msg.sender);
                if(choice) {
                    q.juryAttestations[record].yesCount ++;
                    q.juryAttestations[record].weighedAttestation += int256(reputation.getReputationOf(msg.sender));
                }else {
                    q.juryAttestations[record].noesCount ++;
                    q.juryAttestations[record].weighedAttestation -= int256(reputation.getReputationOf(msg.sender));
                }
            }
            q.attested[msg.sender] = AttestationChoice(record, choice);
            _depositStake(id);
            emit Attested(record);
            return record;
        }
        return 0;
    }

    /**
     * Resolve an attestation after time defined on attestationWindow
     * @param id index of attestation
     */
    function resolve(uint256 id) public onlyInState(id, AttestationState.OPEN) {
        Attestation storage q = attestations[id];
        require(block.timestamp > attestEnd, "too soon");

        //Check unanimity if only one record is uploaded
        if(q.records.length == 1) {
            _checkUnanimity(id);
            return;
        }

        //Get most attested record by users
        int256 mostAttestations;
        for(uint256 i = 0; i < q.records.length; i++) {
            int256 attestationCount = q.userAttestations[q.records[i]].weighedAttestation;
            if(attestationCount > mostAttestations) {
                mostAttestations = attestationCount;
                q.mostAttested = q.records[i];
            }
        }

        //Get most attested record by juries
        int256 mostJuryAttestations;
        for(uint256 i = 0; i < q.records.length; i++) {
            int256 attestationCount = q.juryAttestations[q.records[i]].weighedAttestation;
            if(attestationCount > mostJuryAttestations) {
                mostJuryAttestations = attestationCount;
                q.mostJuryAttested = q.records[i];
            }
        }

        //only users voted
        if(q.usersAttested.length > 0 && q.juriesAttested.length == 0) {
            if(mostAttestations > 0 && q.userAttestations[q.mostAttested].yesCount > 2) {
                q.finalResult = q.mostAttested;
                _setReputation(id);
                q.resolved = AttestationState.CONSENSUAL;
                emit Resolved(id, q.resolved);
            } else {
                q.resolved = AttestationState.VERIFYING;
                emit InitVerification(id);
            }
        }
        //only juries voted
        else if(q.usersAttested.length == 0 && q.juriesAttested.length > 0) {
            if(mostJuryAttestations > 0) {
                q.finalResult = q.mostJuryAttested;
                _setReputation(id);
                q.resolved = AttestationState.CONSENSUAL;
                emit Resolved(id, q.resolved);
            } else {
                q.resolved = AttestationState.VERIFYING;
                emit InitVerification(id);
            }
        }
        //most users match most juries
        else if(q.mostAttested == q.mostJuryAttested) {
            if(mostAttestations > 0 && mostJuryAttestations > 0) {
                q.finalResult = q.mostAttested;
                _setReputation(id);
                q.resolved = AttestationState.CONSENSUAL;
                emit Resolved(id, q.resolved);
            } else {
                q.resolved = AttestationState.VERIFYING;
                emit InitVerification(id);
            }
        }
        //most users doesn't match most juries
        else {
            q.resolved = AttestationState.VERIFYING;
            emit InitVerification(id);
        }
    }

    /**
     * Check unanimity, if all users and juries voted unique record as real,
     * attestation is CLOSED, else if mostly voted real, is OBSERVED.
     * Also sets users/juries reputation.
     * @param id index of attestation
     */
    function _checkUnanimity(uint256 id) private {
        Attestation storage q = attestations[id];
        uint256 record = q.records[0];

        if(
            !(q.userAttestations[record].weighedAttestation > 0 && q.juryAttestations[record].weighedAttestation > 0) &&
            !(q.juriesAttested.length == 0 && q.userAttestations[record].yesCount > 2) &&
            !(q.usersAttested.length == 0 && q.juryAttestations[record].weighedAttestation > 0)
        ){
            q.resolved = AttestationState.VERIFYING;
            emit InitVerification(id);
            return;
        }

        q.finalResult = q.records[0];
        uint256 distributionAmount = q.cumulatedStake / (
            q.userAttestations[q.finalResult].yesCount +
            q.juryAttestations[q.finalResult].yesCount
        );
        
        for(uint256 i = 0; i < q.usersAttested.length; i++) {
            address user = q.usersAttested[i];
            reputation.updateReputation(user, q.attested[user].choice);
            if(q.attested[user].choice) {
                stakeToken.safeTransfer(user, distributionAmount);
            }
        }

        for(uint256 i = 0; i < q.juriesAttested.length; i++) {
            address jury = q.juriesAttested[i];
            reputation.updateReputation(jury, q.attested[jury].choice);
            if(q.attested[jury].choice) {
                stakeToken.safeTransfer(jury, distributionAmount);
            }
        }

        if(q.userAttestations[record].noesCount > 0 || q.juryAttestations[record].noesCount > 0) {
            q.resolved = AttestationState.CONSENSUAL;
        } else {
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
        uint256 finalResult = q.finalResult;
        
        uint256 distributionAmount = q.cumulatedStake / (
            q.userAttestations[finalResult].yesCount +
            q.juryAttestations[finalResult].yesCount
        );

        for(uint256 i = 0; i < q.usersAttested.length; i++) {
            address user = q.usersAttested[i];
            reputation.updateReputation(user, q.attested[user].record == finalResult && q.attested[user].choice);
            if(q.attested[user].record == finalResult && q.attested[user].choice) {
                stakeToken.safeTransfer(user, distributionAmount);
            }
        }

        for(uint256 i = 0; i < q.juriesAttested.length; i++) {
            address user = q.juriesAttested[i];
            reputation.updateReputation(user, q.attested[user].record == finalResult && q.attested[user].choice);
            if(q.attested[user].record == finalResult && q.attested[user].choice) {
                stakeToken.safeTransfer(user, distributionAmount);
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
        if(q.userAttestations[choice].yesCount > 0 || q.juryAttestations[choice].yesCount > 0) {
            q.finalResult = choice;
            _setReputation(id);
            q.resolved = AttestationState.CLOSED;
        }
    }

    /**
    * Resolve all attestations in one callback,
    */
    function resolveAll() external {
        require(block.timestamp > attestEnd, "too soon");
        
        uint256 length = attestations.length;
        for(uint256 i = 0; i < length; i++) {
            resolve(i);
        }
    }

    function getAttestationInfo(uint256 id) external view returns(
        AttestationState resolved, uint256 finalResult
    ){
        Attestation storage q = attestations[id];
        return (q.resolved, q.finalResult);
    }

    function getWeighedAttestations(uint256 id, uint256 record) external view returns(int256) {
        return attestations[id].userAttestations[record].weighedAttestation;
    }

    function getJuryWeighedAttestations(uint256 id, uint256 record) external view returns(int256) {
        return attestations[id].juryAttestations[record].weighedAttestation;
    }

    function getOptionAttested(uint256 id) external view returns(uint256, bool) {
        return (attestations[id].attested[msg.sender].record, attestations[id].attested[msg.sender].choice);
    }

    function viewAttestationResult(uint256 id) external view returns(uint256, uint256) {
        return (attestations[id].mostAttested, attestations[id].mostJuryAttested);
    }

    function setActiveTime(uint256 start, uint256 end) external onlyRole(DEFAULT_ADMIN_ROLE) {
        attestStart = start;
        attestEnd = end;
    }
}

