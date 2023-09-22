// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract CodeJar {
    error CodeSaveFailed(bytes initCode);
    error CodeSaveMismatch(bytes initCode, bytes code, address expected, address created);
    error CodeTooLarge(uint256 sz);
    error CodeNotFound(address codeAddress);

    /**
     * @notice Saves the code to the code jar, if it doesn't already exist
     * @dev This calls it meant to be idemponent and fairly inexpensive on a second call.
     * @return The address of the contract that matches the inputted code.
     */
    function saveCode(bytes calldata code) external returns (address) {
        (address codeAddress, uint256 codeAddressLen, bytes memory initCode, uint256 initCodeLen) = getInitCode(code);

        if (codeAddressLen == 0) {
            address codeCreateAddress;
            assembly {
                codeCreateAddress := create2(0, add(initCode, 32), initCodeLen, 0)
            }

            // Ensure that the wallet was created.
            if (uint160(address(codeCreateAddress)) == 0) {
                revert CodeSaveFailed(initCode);
            }

            if (codeCreateAddress != codeAddress) {
                revert CodeSaveMismatch(initCode, code, codeAddress, codeCreateAddress);
            }
        }

        return codeAddress;
    }

    /**
     * @notice Checks if code already exists in the code jar
     * @return True if code already exists in code jar
     */
    function codeExists(bytes calldata code) external returns (bool) {
        (address codeAddress, uint256 codeAddressLen, bytes memory initCode, uint256 initCodeLen) = getInitCode(code);

        return codeAddressLen > 0;
    }

    // Helper to get the init code and check if the code exists already.
    function getInitCode(bytes memory code) internal returns (address, uint256, bytes memory, uint256) {
        bytes memory initCode = abi.encodePacked(hex"63", uint32(code.length), hex"80600e6000396000f3", code);
        address codeAddress = address(uint160(uint(
            keccak256(
                abi.encodePacked(
                    bytes1(0xff),
                    address(this),
                    uint256(0),
                    keccak256(initCode)
                )
            )))
        );

        uint256 codeAddressLen;
        assembly {
            codeAddressLen := extcodesize(codeAddress)
        }

        return (codeAddress, codeAddressLen, initCode, initCode.length);
    }

    /**
     * @notice Reads the given code from the code jar
     * @dev This simply is an extcodecopy from the address. Reverts if code doesn't exist.
     * @dev This does not check that the address was created by this contract, and thus
     *      will read any contract.
     */
    function readCode(address codeAddress) external view returns (bytes memory) {
        uint256 codeLen;
        assembly {
            codeLen := extcodesize(codeAddress)
        }

        if (codeLen == 0) {
            revert CodeNotFound(codeAddress);
        }

        bytes memory code = new bytes(codeLen);
        assembly {
            extcodecopy(codeAddress, add(code, 0x20), 0, codeLen)
        }

        // TODO: Check that the code was created by this code jar?

        return code;
    }
}

