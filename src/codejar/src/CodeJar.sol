// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {CodeJarStub} from "./CodeJarStub.sol";

/**
 * @title Code Jar
 * @notice Deploys contract code to deterministic addresses
 * @author Compound Labs, Inc.
 */
contract CodeJar {
    /**
     * @notice Deploys the code via Code Jar, no-op if it already exists
     * @dev This call is meant to be idemponent and fairly inexpensive on a second call
     * @param code The runtime bytecode of the code to save
     * @return The address of the contract that matches the input code
     */
    function saveCode(bytes calldata code) external returns (address) {
        address codeAddress = getCodeAddress(code);
        bytes32 codeAddressHash = codeAddress.codehash;

        if (codeAddressHash == keccak256(code)) {
            // Code is already deployed and matches expected code
            return codeAddress;
        } else {
            // The code has not been deployed here (or it was deployed and destructed).
            CodeJarStub script;
            bytes memory initCode = abi.encodePacked(type(CodeJarStub).creationCode, code);
            assembly {
                script := create2(0, add(initCode, 0x20), mload(initCode), 0)
            }

            // Posit: these cannot fail and are purely defense-in-depth
            require(address(script) == codeAddress);

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

        return codeAddress.code.length != 0 && codeAddress.codehash == keccak256(code);
    }

    /**
     * @dev Returns the create2 address based on CodeJarStub
     * @return The create2 address to deploy this code (via CodeJarStub)
     */
    function getCodeAddress(bytes memory code) internal view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            uint256(0),
                            keccak256(abi.encodePacked(type(CodeJarStub).creationCode, code))
                        )
                    )
                )
            )
        );
    }
}