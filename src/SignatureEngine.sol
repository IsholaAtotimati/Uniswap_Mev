// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolKey.sol";
import {EventPublisher} from "./EventPublisher.sol";

abstract contract SignatureEngine is EventPublisher {
    struct LossPayload {
        bytes32 poolId;
        uint256 expectedLpLoss;
        uint256 expectedLeakage;
        uint256 toxicityScore;
        uint24 recommendedSpread;
        address settlementToken;
        uint256 settlementAmount;
        uint32 destinationDomain;
        bytes32 recipient;
        uint256 expiry;
        uint256 nonce;
        address signer;
    }

    struct Attestation {
        address operator;
        bytes signature;
    }

    mapping(address => mapping(uint256 => bool)) public usedNonces;
    mapping(address => bool) public isTrustedSigner;
    uint256 public quorumThreshold;
    address public immutable MULTISIG;

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
    bytes32 public constant LOSS_PAYLOAD_TYPEHASH =
        keccak256(
            "LossPayload(bytes32 poolId,uint256 expectedLpLoss,uint256 expectedLeakage,uint256 toxicityScore,uint24 recommendedSpread,address settlementToken,uint256 settlementAmount,uint32 destinationDomain,bytes32 recipient,uint256 expiry,uint256 nonce,address signer)"
        );
    bytes32 public constant NAME_HASH = keccak256("MEVShieldHook");
    bytes32 public constant VERSION_HASH = keccak256("1");

    error InvalidSignature();
    error ExpiredPayload();
    error ReplayDetected();
    error InvalidPayload();
    error UntrustedSigner();
    error InsufficientQuorum();
    error UnauthorizedSignatureEngine();

    constructor(address _multisig) {
        if (_multisig == address(0)) revert UnauthorizedSignatureEngine();
        MULTISIG = _multisig;
        quorumThreshold = 1;
    }

    modifier onlyMultisig() {
        if (msg.sender != MULTISIG) revert UnauthorizedSignatureEngine();
        _;
    }

    function setTrustedSigner(address signer, bool trusted) external onlyMultisig {
        if (signer == address(0)) revert InvalidPayload();
        isTrustedSigner[signer] = trusted;
        emit TrustedSignerUpdated(signer, trusted);
    }

    function setQuorumThreshold(uint256 threshold) external onlyMultisig {
        if (threshold == 0) revert InvalidPayload();
        quorumThreshold = threshold;
    }

    function _hashBytes(bytes memory data) internal pure returns (bytes32 hash) {
        assembly {
            hash := keccak256(add(data, 0x20), mload(data))
        }
    }

    function _domainSeparator() internal view returns (bytes32) {
        return _hashBytes(
            abi.encode(
                DOMAIN_TYPEHASH,
                NAME_HASH,
                VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    function _hashPayload(LossPayload memory payload) internal pure returns (bytes32) {
        return _hashBytes(
            abi.encode(
                LOSS_PAYLOAD_TYPEHASH,
                payload.poolId,
                payload.expectedLpLoss,
                payload.expectedLeakage,
                payload.toxicityScore,
                payload.recommendedSpread,
                payload.settlementToken,
                payload.settlementAmount,
                payload.destinationDomain,
                payload.recipient,
                payload.expiry,
                payload.nonce,
                payload.signer
            )
        );
    }

    function _recoverSigner(bytes32 digest, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) revert InvalidSignature();

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            let ptr := add(signature, 0x20)
            r := mload(ptr)
            s := mload(add(ptr, 0x20))
            v := byte(0, mload(add(ptr, 0x40)))
        }

        return ecrecover(digest, v, r, s);
    }

    function _verifyPayload(
        PoolKey calldata key,
        LossPayload memory payload,
        Attestation[] memory attestations
    ) internal {
        if (payload.expiry < block.timestamp) revert ExpiredPayload();
        if (payload.recommendedSpread > 20000) revert InvalidPayload();
        if (payload.poolId != keccak256(abi.encode(key.toId()))) revert InvalidPayload();

        if (attestations.length < quorumThreshold) revert InsufficientQuorum();

        bytes32 payloadHash = _hashPayload(payload);
        bytes32 digest = _hashBytes(abi.encodePacked("\x19\x01", _domainSeparator(), payloadHash));

        address[] memory seenOperators = new address[](attestations.length);
        uint256 seenCount;

        for (uint256 i; i < attestations.length; ++i) {
            address operator = attestations[i].operator;
            if (operator == address(0)) revert InvalidPayload();
            if (!isTrustedSigner[operator]) revert UntrustedSigner();

            for (uint256 j; j < seenCount; ++j) {
                if (seenOperators[j] == operator) revert InvalidPayload();
            }

            seenOperators[seenCount++] = operator;

            address recovered = _recoverSigner(digest, attestations[i].signature);
            if (recovered != operator) revert InvalidSignature();

            if (usedNonces[operator][payload.nonce]) revert ReplayDetected();
            usedNonces[operator][payload.nonce] = true;
        }

        emit PriceVerified(payload.poolId, payload.signer, payload.nonce);
    }
}
