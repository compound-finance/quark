// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract CodeJar {
    error CodeTooLarge(uint256 sz);
    error CodeNotFound(address codeAddress);
    error CodeInvalid(address codeAddress);
    error CodeHashMismatch(address codeAddress, bytes32 expected, bytes32 given);

    /**
     * @notice Saves the code to the code jar, no-op if it already exists
     * @dev This calls it meant to be idemponent and fairly inexpensive on a second call.
     * @return The address of the contract that matches the input code.
     */
    function saveCode(bytes calldata code) external returns (address) {
        bytes memory initCode = getInitCode(code);
        address codeAddress = getCodeAddress(initCode);
        bytes32 codeAddressHash = codeAddress.codehash;

        if (codeAddressHash == 0) {
            // The code has not been deployed here (or it was deployed and destructed).
            address codeCreateAddress;
            uint256 initCodeLen = initCode.length;
            assembly {
                codeCreateAddress := create2(0, add(initCode, 32), initCodeLen, 0)
            }

            // Posit: these cannot fail and are purely defense-in-depth
            require(codeCreateAddress != address(0));
            require(codeCreateAddress == codeAddress);

            return codeAddress;
        } else if (codeAddressHash == keccak256(code)) {
            // Code is already deployed and matches expected code
            return codeAddress;
        } else {
            // Code is already deployed but does not match expected code.
            // Note: this should never happen except if the initCode script
            //       has an unknown bug.
            revert CodeHashMismatch(codeAddress, keccak256(code), codeAddressHash);
        }
    }

    /**
     * @notice Checks if code already exists in the code jar
     * @return True if code already exists in code jar
     */
    function codeExists(bytes calldata code) external view returns (bool) {
        bytes memory initCode = getInitCode(code);
        address codeAddress = getCodeAddress(initCode);

        return codeAddress.codehash == keccak256(code);
    }

    /// Returns initCode that would produce `code` as its output. See the
    /// full contract specification for in-depth details.
    function getInitCode(bytes memory code) internal pure returns (bytes memory) {
        // Note: The gas cost in memory is `O(a^2)`, thus for an array to be
        //       more than 2^32 bytes long, the gas cost would be (2^32)^2 or
        //       about 13 orders of magnitude above the current block gas
        //       limit. As such, we check the type-conversion, but understand
        //       it is not possible to accept a value whose length whose length
        //       would not actually fit in 32-bits.
        require(code.length < type(uint32).max);
        uint32 codeLen = uint32(code.length);

        return abi.encodePacked(hex"63", codeLen, hex"80600e6000396000f3", code);
    }

    /// This is simply the create2 address based on running the initCode constructor.
    function getCodeAddress(bytes memory initCode) internal view returns (address) {
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
     */
    function readCode(address codeAddress) external view returns (bytes memory) {
        bytes memory code = codeAddress.code;

        // Check that address where that given code would have been created by this contract
        bytes memory initCode = getInitCode(code);

        // Revert if the code doesn't match where we should have deployed it.
        // This is to prevent using this contract to read random contract codes.
        if (getCodeAddress(initCode) != codeAddress) {
            revert CodeInvalid(codeAddress);
        }

        return code;
    }
}
