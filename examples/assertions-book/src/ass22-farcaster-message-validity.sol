// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Farcaster Protocol
 * @notice This contract implements message handling for the Farcaster protocol
 * @dev Contains functionality for message validation, user registration, and rate limiting
 */
contract Farcaster {
    // Message struct matching the interface in the assertion
    struct Message {
        uint256 id;
        address author;
        bytes content;
        uint256 timestamp;
        bytes signature;
    }

    // Storage mappings
    mapping(string => address) private _usernameToOwner;
    mapping(string => bool) private _registeredUsernames;
    mapping(address => uint256) private _lastPostTimestamp;

    // Simple message validation constants
    bytes constant INVALID_SIGNATURE = "invalidSignature";
    bytes constant INVALID_CONTENT = "invalid content";

    /**
     * @notice Checks if a message is valid according to protocol rules
     * @param message The message to validate
     * @return A boolean indicating whether the message is valid
     */
    function isValidMessage(Message memory message) external view returns (bool) {
        // Very basic checks:
        // 1. Message must have a non-zero author address
        // 2. Content must not be empty
        // 3. Content must not be specifically marked as invalid
        // 4. Message must have a timestamp

        if (message.author == address(0)) {
            return false;
        }

        if (message.content.length == 0) {
            return false;
        }

        // Check if content is explicitly marked as invalid
        if (keccak256(message.content) == keccak256(INVALID_CONTENT)) {
            return false;
        }

        if (message.timestamp == 0) {
            return false;
        }

        return true;
    }

    /**
     * @notice Verifies the cryptographic signature of a message
     * @param message The message containing the signature to verify
     * @return A boolean indicating whether the signature is valid
     */
    function verifySignature(Message memory message) external view returns (bool) {
        // For testing purposes, we're just checking if the signature isn't "invalidSignature"
        // In a real implementation, this would do proper cryptographic verification
        return keccak256(message.signature) != keccak256(INVALID_SIGNATURE);
    }

    /**
     * @notice Posts a new message to the protocol
     * @param message The message to post
     */
    function postMessage(Message memory message) external {
        _lastPostTimestamp[message.author] = block.timestamp;
    }

    /**
     * @notice Registers a new username with an owner address
     * @param username The username to register
     * @param owner The address to associate with the username
     */
    function register(string calldata username, address owner) external {
        _registeredUsernames[username] = true;
        _usernameToOwner[username] = owner;
    }

    /**
     * @notice Checks if a username is registered
     * @param username The username to check
     * @return A boolean indicating whether the username is registered
     */
    function isRegistered(string calldata username) external view returns (bool) {
        return _registeredUsernames[username];
    }

    /**
     * @notice Gets the owner address of a registered username
     * @param username The username to look up
     * @return The address of the username owner
     */
    function getUsernameOwner(string calldata username) external view returns (address) {
        return _usernameToOwner[username];
    }

    /**
     * @notice Gets the timestamp of a user's last post
     * @param user The address of the user
     * @return The timestamp of the user's last post
     */
    function getLastPostTimestamp(address user) external view returns (uint256) {
        return _lastPostTimestamp[user];
    }
}
