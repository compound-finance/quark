// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

/**
 * @title Code Jar
 * @notice Deploys contract code to deterministic addresses
 * @author Compound Labs, Inc.
 */
contract CodeJar {
    /**
     * @notice Deploys the code via Code Jar, no-op if it already exists
     * @dev This call is meant to be idemponent and fairly inexpensive on a second call
     * @param code The creation bytecode of the code to save
     * @return The address of the contract that matches the input code's contructor output
     */
    function saveCode(bytes memory code) external returns (address) {
        address codeAddress = getCodeAddress(code);

        if (codeAddress.code.length > 0) {
            // Code is already deployed
            return codeAddress;
        } else {
            // The code has not been deployed here (or it was deployed and destructed).
            address script;
            assembly {
                script := create2(0, add(code, 0x20), mload(code), 0)
            }

            // Posit: these cannot fail and are purely defense-in-depth
            require(script == codeAddress);

            uint256 scriptSz;
            assembly {
                scriptSz := extcodesize(script)
            }

            // Disallow the empty code
            // Note: script can still selfdestruct
            require(scriptSz > 0);

            return codeAddress;
        }
    }

    /**
     * @notice Checks if code was already deployed by CodeJar
     * @param code The runtime bytecode of the code to check
     * @return True if code already exists in Code Jar
     */
    function codeExists(bytes calldata code) external view returns (bool) {
        address codeAddress = getCodeAddress(code);

        return codeAddress.code.length > 0;
    }

    /**
     * @dev Returns the create2 address based on the creation code
     * @return The create2 address to deploy this code (via init code)
     */
    function getCodeAddress(bytes memory code) public view returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), uint256(0), keccak256(code)))))
        );
    }
}
