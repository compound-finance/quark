// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

contract CodeJar {
    error CodeInvalid(address codeAddress);
    error CodeHashMismatch(address codeAddress, bytes32 expected, bytes32 given);

    /**
     * @notice Saves the code to Code Jar, no-op if it already exists
     * @dev This call is meant to be idemponent and fairly inexpensive on a second call
     * @param code The runtime bytecode of the code to save
     * @return The address of the contract that matches the input code
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
     * @notice Checks if code already exists in Code Jar
     * @dev Use `saveCode` to get the address of the contract with that code
     * @param code The runtime bytecode of the code to check
     * @return True if code already exists in Code Jar
     */
    function codeExists(bytes calldata code) external view returns (bool) {
        bytes memory initCode = getInitCode(code);
        address codeAddress = getCodeAddress(initCode);

        return codeAddress.codehash == keccak256(code);
    }

    /**
     * @dev Builds the initCode that would produce `code` as its output.
     * @dev See the full contract specification for in-depth details.
     * @return initCode that would produce  `code` as its output
     */
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

    /**
     * @dev Returns the create2 address based on the given initCode
     * @return The create2 address based on running the initCode constructor
     */
    function getCodeAddress(bytes memory initCode) internal view returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), uint256(0), keccak256(initCode)))))
        );
    }
}
