// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IBurnMintToken {
    function burnFrom(address from, uint256 amount) external;
    function mint(address to, uint256 amount) external;
}

interface IAttestationVerifier {
    /// @notice Validate and parse an attestation
    /// @return token The token address to burn/mint
    /// @return amount The amount to burn/mint
    /// @return recipient The recipient on this chain to mint to
    function verifyAttestation(bytes calldata attestation) external returns (address token, uint256 amount, address recipient);
}

interface ISettlementCoordinator {
    function settlements(bytes32) external view returns (uint256 amount, uint32 destinationDomain, address token, bool settled);
    function cctpMessageIds(bytes32) external view returns (bytes32 messageId);
    function markAwaitingAttestation(bytes32 settlementId) external;
    function markMintSubmitted(bytes32 settlementId) external;
    function completeSettlement(bytes32 settlementId) external;
}

contract CCTPAdapter {
    address public owner;
    IAttestationVerifier public verifier;
    ISettlementCoordinator public settlementCoordinator;

    error Unauthorized();
    error InvalidAttestation();
    error BurnFailed();
    error SettlementMismatch();

    event AttestationProcessed(bytes32 indexed attestationHash, address token, uint256 amount, address recipient);
    event AttestationReceived(bytes32 indexed settlementId, bytes32 indexed attestationHash, address token, uint256 amount, address recipient);
    event USDCMintCompleted(bytes32 indexed settlementId, address token, uint256 amount, address recipient);
    event CrossChainSettlementCompleted(bytes32 indexed settlementId, bytes32 indexed cctpMessageId);
    event VerifierUpdated(address indexed verifier);
    event SettlementFinalized(bytes32 indexed settlementId, address token, uint256 amount);

    constructor(address _verifier) {
        owner = msg.sender;
        if (_verifier != address(0)) verifier = IAttestationVerifier(_verifier);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    function setVerifier(address _verifier) external onlyOwner {
        verifier = IAttestationVerifier(_verifier);
        emit VerifierUpdated(_verifier);
    }

    function setSettlementCoordinator(address _coordinator) external onlyOwner {
        settlementCoordinator = ISettlementCoordinator(_coordinator);
    }

    /// @notice Process a CCTP attestation: burn source USDC and mint destination USDC
    /// @param attestation Encoded attestation produced by CCTP (structure validated by verifier)
    /// @return success True if processing succeeded
    function processAttestation(bytes calldata attestation) external returns (bool success) {
        return _processAttestation(attestation, bytes32(0));
    }

    function processAttestation(bytes calldata attestation, bytes32 settlementId) external returns (bool success) {
        return _processAttestation(attestation, settlementId);
    }

    function _processAttestation(bytes calldata attestation, bytes32 settlementId) internal returns (bool success) {
        if (address(verifier) == address(0)) revert InvalidAttestation();

        (address token, uint256 amount, address recipient) = verifier.verifyAttestation(attestation);

        if (token == address(0) || amount == 0) revert InvalidAttestation();

        bytes32 attestationHash = keccak256(attestation);

        if (settlementId != bytes32(0) && address(settlementCoordinator) != address(0)) {
            (uint256 settlementAmount, uint32 settlementDomain, address settlementToken, bool settled) =
                settlementCoordinator.settlements(settlementId);

            if (settlementAmount != amount || settlementToken != token || settled) revert SettlementMismatch();

            emit AttestationReceived(settlementId, attestationHash, token, amount, recipient);
            settlementCoordinator.markMintSubmitted(settlementId);
        }

        IBurnMintToken burnMint = IBurnMintToken(token);
        burnMint.burnFrom(msg.sender, amount);
        burnMint.mint(recipient, amount);

        if (settlementId != bytes32(0) && address(settlementCoordinator) != address(0)) {
            settlementCoordinator.completeSettlement(settlementId);
            emit SettlementFinalized(settlementId, token, amount);
            emit USDCMintCompleted(settlementId, token, amount, recipient);
            emit CrossChainSettlementCompleted(settlementId, settlementCoordinator.cctpMessageIds(settlementId));
        }

        emit AttestationProcessed(attestationHash, token, amount, recipient);
        return true;
    }
}
