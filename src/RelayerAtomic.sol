// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Relayer.sol";
import "./QuarkScript.sol";
import "./QuarkWallet.sol";

contract RelayerAtomic is Relayer {
    error QuarkAlreadyActive(address quark);
    error QuarkNotActive(address quark);
    error QuarkInvalid(address quark, bytes32 isQuarkScriptHash);
    error QuarkInitFailed(address quark, bool create2Failed);
    error QuarkCallFailed(address quark, bytes error);
    error QuarkAddressMismatch(address expected, address created);

    mapping(address => address) public quarkCodes;

    constructor(CodeJar codeJar_) Relayer(codeJar_) {}

    /**
     * @notice Helper function to return a quark address for a given account.
     */
    function getQuarkAddress(address account) public view override returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            uint256(0),
                            keccak256(
                                abi.encodePacked(
                                    type(QuarkWallet).creationCode, abi.encode(account), abi.encode(address(codeJar))
                                )
                            )
                        )
                    )
                )
            )
        );
    }

    // Saves quark code for an quark address into storage. This is required
    // since we can't pass unique quark code in the `create2` constructor,
    // since it would end up at a different wallet address.
    function saveQuark(address quarkAddress, bytes memory quarkCode) internal {
        quarkCodes[quarkAddress] = codeJar.saveCode(quarkCode);
    }

    /**
     * @notice Returns the code associated with a running quark for `msg.sender`
     * @dev This is generally expected to be used only by the Quark wallet itself
     *      in the constructor phase to get its code.
     */
    function readQuarkCodeAddress() external view returns (address) {
        address quarkAddress = msg.sender;
        address quarkCodeAddress = quarkCodes[quarkAddress];
        if (quarkCodeAddress == address(0)) {
            revert QuarkNotActive(quarkAddress);
        }
        return quarkCodeAddress;
    }

    // Clears quark data a) to save gas costs, and b) so another quark can
    // be run for the same quarkAddress in the future.
    function clearQuark(address quarkAddress) internal {
        quarkCodes[quarkAddress] = address(0);
    }

    // Internal function for running a quark. This handles the `create2`, invoking the script,
    // and then calling `destruct` to clean it up. We attempt to revert on any failed step.
    function _runQuark(address account, bytes memory quarkCode, bytes memory quarkCalldata)
        internal
        override
        returns (bytes memory)
    {
        address quarkAddress = getQuarkAddress(account);

        // Ensure a quark isn't already running
        if (quarkCodes[quarkAddress] != address(0)) {
            revert QuarkAlreadyActive(quarkAddress);
        }

        // Stores the quark in storage so it can be loaded via `readQuark` in the `create2`
        // constructor code (see `./Quark.yul`).
        saveQuark(quarkAddress, quarkCode);

        uint256 existingQuarkSize;

        assembly {
            existingQuarkSize := extcodesize(quarkAddress)
        }

        address quark;
        if (existingQuarkSize > 0) {
            quark = quarkAddress;
        } else {
            // The call to `create2` that creates the (temporary) quark wallet.
            quark = address(new QuarkWallet{salt: 0}(account, codeJar));

            // Ensure that the wallet was created.
            if (uint160(address(quark)) == 0) {
                revert QuarkInitFailed(quarkAddress, true);
            }

            if (quarkAddress != address(quark)) {
                revert QuarkAddressMismatch(quarkAddress, address(quark));
            }
        }

        // Call into the new quark wallet with a (potentially empty) message to hit the fallback function.
        (bool callSuccess, bytes memory res) = address(quark).call{value: msg.value}(quarkCalldata);
        if (!callSuccess) {
            revert QuarkCallFailed(quarkAddress, res);
        }

        clearQuark(quarkAddress);

        // We return the result from the call, but it's not particularly important.
        return res;
    }
}
