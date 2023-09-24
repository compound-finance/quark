// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract CodeJar {
    error CodeTooLarge(uint256 sz);
    error CodeNotFound(address codeAddress);

    /**
     * @notice Saves the code to the code jar, if it doesn't already exist
     * @dev This calls it meant to be idemponent and fairly inexpensive on a second call.
     * @return The address of the contract that matches the inputted code.
     */
    function saveCode(bytes calldata code) external returns (address) {
        bytes memory initCode = getInitCode(code);
        address codeAddress = getCodeAddress(initCode);

        // Note: we could check without codehash which costs extra gas, but
        //       the additional check to make sure the code hash matches expectation
        //       seems valuable.
        if (codeAddress.codehash == keccak256(code)) {
            // Code is already deployed and matches expected code
            return codeAddress;
        } else {
            // Note: this branch technically could be triggered if there were ever invalid code
            //       at the script address (i.e. it didn't match the input code).
            address codeCreateAddress;
            uint256 initCodeLen = initCode.length;
            assembly {
                codeCreateAddress := create2(0, add(initCode, 32), initCodeLen, 0)
            }

            // Posit: these cannot fail and are purely defense-in-depth
            require(codeCreateAddress != address(0));
            require(codeCreateAddress == codeAddress);

            return codeAddress;
        }
    }

    /**
     * @notice Checks if code already exists in the code jar
     * @return True if code already exists in code jar
     */
    function codeExists(bytes calldata code) external returns (bool) {
        bytes memory initCode = getInitCode(code);
        address codeAddress = getCodeAddress(initCode);

        return codeAddress.codehash == keccak256(code);
    }

    function getInitCode(bytes memory code) internal returns (bytes memory) {
        // Note: The gas cost in memory is `O(a^2)`, thus for an array to be more than 2^32 bytes long, the gas cost
        //       would be (2^32)^2 or about 13 orders of magnitude above the current block gas limit. As such,
        //       we rely on check the conversion, but understand it is not possible to accept a value
        //       whose length would not actually fit in 32 bits.
        require(code.length <= type(uint32).max);
        uint32 codeLen = uint32(code.length);
        
        return abi.encodePacked(hex"63", codeLen, hex"80600e6000396000f3", code);
    }

    function getCodeAddress(bytes memory initCode) internal returns (address) {
        return address(uint160(uint(
            keccak256(
                abi.encodePacked(
                    bytes1(0xff),
                    address(this),
                    uint256(0),
                    keccak256(initCode)
                )
            )))
        );
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

        // TODO: the hex"" empty byte string would incorrectly fail here.
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

