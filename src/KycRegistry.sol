
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * SBT intransferible. El backend firma (wallet, idHash) y el usuario reclama.
 */
contract KycRegistry is ERC721 {
    mapping(address => bytes32) public idHashOf;
    address public immutable backendSigner;

    error AlreadyRegistered();
    error InvalidSignature();

    constructor(address _backendSigner)
        ERC721("VerifiedIdentity", "VID")
    {
        backendSigner = _backendSigner;
    }

    /**
     * Reclama tu SBT.
     * @param idHash  keccak256(DNI)
     * @param sig     firma del backend sobre (msg.sender, idHash)
     */
    function claim(bytes32 idHash, bytes calldata sig) external {
        if (balanceOf(msg.sender) > 0) revert AlreadyRegistered();

        bytes32 h = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n84", msg.sender, idHash)
        );
        if (ECDSA.recover(h, sig) != backendSigner) revert InvalidSignature();

        idHashOf[msg.sender] = idHash;
        _safeMint(msg.sender, uint160(msg.sender));
    }

    /**
     * Para OZ v5.x hay que sobreescribir _update en lugar de _beforeTokenTransfer.
     * Esto impide transferencias posteriores.
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address from) {
        // llama al hook base, que devuelve el owner previo
        from = super._update(to, tokenId, auth);
        // sólo permitimos mintear (from==0) o quemar (to==0)
        require(from == address(0) || to == address(0), "SBT not transferable");
    }
}
