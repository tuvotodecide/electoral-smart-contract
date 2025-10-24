
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IMintableERC721} from "../../src/interfaces/IMintableERC721.sol";
import {IReputation} from "./IReputationV2.sol";
import {IWiraToken} from "../../src/interfaces/IWiraToken.sol";

/// @custom:oz-upgrades-from src/AttestationOracle.sol:AttestationOracle
contract AttestationOracleV2 is Initializable, UUPSUpgradeable, OwnableUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
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
        CLOSED,
        PENDING
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

    IMintableERC721 public attestationRecord;
    IReputation public reputation;
    IWiraToken public stakeToken;
    uint256 public stake;
    uint256 public totalAttestations;
    mapping(string => Attestation) private attestations;
    uint256 public attestationWindow; //time for attestations

    struct AttestationTime {
        uint256 start;
        uint256 end;
    }
    mapping(string => AttestationTime) private attestationsTimes;


    event RegisterRequested(address user, string uri);
    event AttestationCreated(string id, uint256 recordId);
    event Attested(uint256 recordId);
    event ReputationUpdated(string id, address user, bool up);
    event Resolved(string id, AttestationState closeState);
    event InitVerification(string id);

    function initialize(
        address defaultAdmin,
        address _attestationRecord,
        address _reputation,
        address _stakeToken,
        uint256 _stake
    ) public initializer {
        __AccessControl_init();
        __Ownable_init(defaultAdmin);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        attestationRecord = IMintableERC721(_attestationRecord);
        reputation = IReputation(_reputation);
        stakeToken = IWiraToken(_stakeToken);
        stake = _stake;
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    modifier onlyActive() {
        require(block.timestamp > attestStart && block.timestamp < attestStart + attestationWindow, "Oracle inactive");
        _;
    }

    modifier onlyVerified() {
        require(hasRole(USER_ROLE, msg.sender) || hasRole(JURY_ROLE, msg.sender), "Unauthorized");
        _;
    }

    modifier onlyInState(string calldata id, AttestationState state) {
        require(attestations[id].resolved == state, "Bad attestation state");
        _;
    }

    //External call by user to init register
    function requestRegister(string calldata uri) external onlyActive {
        if(!hasRole(USER_ROLE, msg.sender) && !hasRole(JURY_ROLE, msg.sender)) {
            emit RegisterRequested(msg.sender, uri);
        }
    }

    //Private call to finish user registering and init reputation
    function register(address user, bool jury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(jury ? JURY_ROLE:USER_ROLE, user);
        reputation.removeReputationOf(user);
        reputation.initReputationOf(user);
    }

    /**
     * make a stake deposit of an attestation to redistribute on resolve
     */
    function _depositStake(string calldata id) private {
        attestations[id].cumulatedStake += stake;
        stakeToken.mint(address(this), stake);
    }

    /**
     * Create a new attestation
     * @param id attestation identifier
     * @param uri a string of IPFS json containing record image and data
     */
    function createAttestation(string calldata id, string calldata uri)
        external
        nonReentrant
        onlyVerified
        onlyActive
        returns (uint256 recordId)
    {
        Attestation storage q = attestations[id];
        require(q.records.length == 0, "Record already created");

        //mint new NFT for record
        recordId = attestationRecord.safeMint(msg.sender, uri);
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
        attestationsTimes[id].start = block.timestamp;

        totalAttestations++;
        //deposit first stake
        _depositStake(id);
        emit AttestationCreated(id, recordId);
    }

    /**
     * Participate on existing attestation, setting as real or fake an uploaded record or uploading a new record
     * @param id attestation identifier
     * @param record record chosen
     * @param choice attest selected record as real or fake
     * @param uri IPFS json of new record to attest as real, if uploaded, record and choice are ignored
     */
    function attest(string calldata id, uint256 record, bool choice, string calldata uri)
        external
        nonReentrant
        onlyVerified
        onlyActive
        onlyInState(id, AttestationState.OPEN)
        returns(uint256)
    {
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
     * @param id attestation identifier
     */
    function resolve(string calldata id) public nonReentrant onlyInState(id, AttestationState.OPEN) {
        Attestation storage q = attestations[id];
        require(block.timestamp > attestEnd, "too soon");

        //Check unanimity if only one record is uploaded
        if(q.records.length == 1) {
            _checkUnanimity(id);
            return;
        }

        //Get most attested record by users and juries
        int256 mostAttestations;
        int256 mostJuryAttestations;
        uint8 tiesCount;
        uint8 juryTiesCount;
        for(uint256 i = 0; i < q.records.length; i++) {
            uint256 record = q.records[i];
            int256 userCount = q.userAttestations[record].weighedAttestation;
            int256 juryCount = q.juryAttestations[record].weighedAttestation;
            if(userCount > mostAttestations) {
                mostAttestations = userCount;
                q.mostAttested = record;
                tiesCount = 0;
            } else if (userCount == mostAttestations) {
                tiesCount++;
            }
            if(juryCount > mostJuryAttestations) {
                mostJuryAttestations = juryCount;
                q.mostJuryAttested = record;
                juryTiesCount = 0;
            } else if(juryCount == mostJuryAttestations) {
                juryTiesCount++;
            }
        }
        
        //check ties
        if(tiesCount > 0 && juryTiesCount > 0) {
            q.resolved = AttestationState.VERIFYING;
            emit InitVerification(id);
            return;
        }

        //only users voted
        if(q.usersAttested.length > 0 && q.juriesAttested.length == 0) {
            if(mostAttestations > 0 && tiesCount == 0) {
                q.finalResult = q.mostAttested;
                q.resolved = q.userAttestations[q.mostAttested].yesCount > 2 ? AttestationState.CONSENSUAL : AttestationState.PENDING;
                _setReputation(id);
                emit Resolved(id, q.resolved);
            } else {
                q.resolved = AttestationState.VERIFYING;
                emit InitVerification(id);
            }
        }
        //only juries voted
        else if(q.usersAttested.length == 0 && q.juriesAttested.length > 0) {
            if(mostJuryAttestations > 0 && juryTiesCount == 0) {
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
        else if(q.mostAttested == q.mostJuryAttested && tiesCount == 0 && juryTiesCount == 0) {
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
        //users tie but juries not
        else if (tiesCount > 0 && juryTiesCount == 0) {
            uint256[] memory userTieRecords = new uint256[](tiesCount + 1);
            uint8 userIndex = 0;
            for(uint256 i = 0; i < q.records.length; i++) {
                uint256 record = q.records[i];
                int256 userCount = q.userAttestations[record].weighedAttestation;
                if(userCount == mostAttestations) {
                    userTieRecords[userIndex] = record;
                    userIndex++;
                }
            }

            if(_checkIsInRecords(q.mostJuryAttested, userTieRecords)) {
                q.finalResult = q.mostJuryAttested;
                _setReputation(id);
                q.resolved = AttestationState.CONSENSUAL;
                emit Resolved(id, q.resolved);
            }else{
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

    function _checkIsInRecords(uint256 record, uint256[] memory array) private pure returns(bool) {
        for(uint256 i = 0; i < array.length; i++) {
            if(array[i] == record) {
                return true;
            }
        }
        return false;
    }

    /**
     * Check unanimity, if all users and juries voted unique record as real,
     * attestation is CLOSED, else if mostly voted real, is OBSERVED.
     * Also sets users/juries reputation.
     * @param id attestation identifier
     */
    function _checkUnanimity(string calldata id) private {
        Attestation storage q = attestations[id];
        uint256 record = q.records[0];

        if(q.userAttestations[record].weighedAttestation <= 0 && q.juryAttestations[record].weighedAttestation <= 0){
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
            bool up = q.attested[user].choice;
            reputation.updateReputation(user, up);
            emit ReputationUpdated(id, user, up);
            if(up) {
                stakeToken.safeTransfer(user, distributionAmount);
            }
        }

        for(uint256 i = 0; i < q.juriesAttested.length; i++) {
            address jury = q.juriesAttested[i];
            bool up = q.attested[jury].choice;
            reputation.updateReputation(jury, up);
            emit ReputationUpdated(id, jury, up);
            if(up) {
                stakeToken.safeTransfer(jury, distributionAmount);
            }
        }

        if(q.juriesAttested.length == 0 && q.userAttestations[record].yesCount <= 2) {
            q.resolved = AttestationState.PENDING;
        } else if(q.userAttestations[record].noesCount > 0 || q.juryAttestations[record].noesCount > 0) {
            q.resolved = AttestationState.CONSENSUAL;
        } else {
            q.resolved = AttestationState.CLOSED;
        }

        attestationsTimes[id].end = block.timestamp;
    }

    /**
     * Update users/juries reputation given an attestation with a final result
     * @param id attestation identifier
     */
    function _setReputation(string calldata id) internal {
        Attestation storage q = attestations[id];
        require(q.finalResult != 0, "Not final set");
        uint256 finalResult = q.finalResult;

        uint256 distributionAmount = q.cumulatedStake / (
            q.userAttestations[finalResult].yesCount +
            q.juryAttestations[finalResult].yesCount
        );

        for(uint256 i = 0; i < q.usersAttested.length; i++) {
            address user = q.usersAttested[i];
            bool up = q.attested[user].record == finalResult && q.attested[user].choice;
            reputation.updateReputation(user, up);
            emit ReputationUpdated(id, user, up);
            if(up) {
                stakeToken.safeTransfer(user, distributionAmount);
            }
        }

        for(uint256 i = 0; i < q.juriesAttested.length; i++) {
            address user = q.juriesAttested[i];
            bool up = q.attested[user].record == finalResult && q.attested[user].choice;
            reputation.updateReputation(user, up);
            emit ReputationUpdated(id, user, up);
            if(up) {
                stakeToken.safeTransfer(user, distributionAmount);
            }
        }

        attestationsTimes[id].end = block.timestamp;
    }

    /**
    * Set final result for VERIFYING attestation,
    * only callable by AUTHORITIES
    * @param id attestation identifier
    * @param choice record selected as real
    */
    function verifyAttestation(string calldata id, uint256 choice) external nonReentrant onlyRole(AUTHORITY_ROLE) onlyInState(id, AttestationState.VERIFYING) {
        Attestation storage q = attestations[id];
        if(q.userAttestations[choice].yesCount > 0 || q.juryAttestations[choice].yesCount > 0) {
            q.finalResult = choice;
            _setReputation(id);
            q.resolved = AttestationState.CLOSED;
        }
    }

    function getAttestationInfo(string calldata id) external view returns(
        AttestationState resolved, uint256 finalResult, uint256 startTime, uint256 endTime
    ){
        Attestation storage q = attestations[id];
        AttestationTime storage t = attestationsTimes[id];
        return (q.resolved, q.finalResult, t.start, t.end);
    }

    function getWeighedAttestations(string calldata id, uint256 record) external view returns(int256) {
        return attestations[id].userAttestations[record].weighedAttestation;
    }

    function getJuryWeighedAttestations(string calldata id, uint256 record) external view returns(int256) {
        return attestations[id].juryAttestations[record].weighedAttestation;
    }

    function getOptionAttested(string calldata id) external view returns(uint256, bool) {
        return (attestations[id].attested[msg.sender].record, attestations[id].attested[msg.sender].choice);
    }

    function viewAttestationResult(string calldata id) external view returns(uint256, uint256) {
        return (attestations[id].mostAttested, attestations[id].mostJuryAttested);
    }

    function setActiveTime(uint256 start, uint256 window) external onlyRole(DEFAULT_ADMIN_ROLE) {
        attestStart = start;
        attestationWindow = window;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

