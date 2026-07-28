// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CCTPAdapter} from "./CCTPAdapter.sol";

/// @notice Backward-compatible shim that preserves the old `CCTPConnector` name
/// while exposing the adapter-oriented architecture explicitly.
contract CCTPConnector is CCTPAdapter {
    constructor(address _verifier) CCTPAdapter(_verifier) {}
}
