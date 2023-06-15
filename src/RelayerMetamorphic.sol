// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Relayer.sol";
import "./QuarkScript.sol";

interface DestructableQuark {
    function destruct() external;
}

contract RelayerMetamorphic is Relayer {
    error QuarkAlreadyActive(address quark);
    error QuarkNotActive(address quark);
    error QuarkInvalid(address quark, bytes32 isQuarkScriptHash);
    error QuarkInitFailed(address quark, bool create2Failed);
    error QuarkCallFailed(address quark, bytes error);
    error QuarkAddressMismatch(address expected, address created);

    mapping(address => uint256) public quarkSizes;
    mapping(address => mapping(uint256 => bytes32)) quarkChunks;

    /**
     * @notice Helper function to return a quark address for a given account.
     */
    function getQuarkAddress(address account) public override view returns (address) {
        return address(uint160(uint(
            keccak256(
                abi.encodePacked(
                    bytes1(0xff),
                    address(this),
                    uint256(0),
                    keccak256(
                        abi.encodePacked(
                            getQuarkInitCode(),
                            abi.encode(account)
                        )
                    )
                )
            )))
        );
    }

    /**
     * @notice The init code for a Quark wallet.
     * @dev The actual init code for a Quark wallet, passed to `create2`. This is
     *      the yul output from `./Quark.yul`, but it's impossible to reference
     *      a yul object in Solidity, so we do a two phase compile where we
     *      build that code, take the outputed bytecode and paste it in here.
     */
    function getQuarkInitCode() public override pure returns (bytes memory) {
        return hex"6100076100f7565b60206102df823951600080600461001c610114565b61002581610191565b82335af1156100ed573d608381019190603f198082019060c361004786610131565b94836040873e7f3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db811155337f46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f655845160d01c653030305050501480156100e9576001146100ae57005b6100e79360066101b687396100c7603e19820187610164565b8501916101bc908301396100de603d19820161014d565b60391901610164565bf35b8386f35b606061027f6101ac565b60405190811561010b575b60208201604052565b60609150610102565b604051908115610128575b60048201604052565b6060915061011f565b90604051918215610144575b8201604052565b6060925061013d565b600360059160006001820153600060028201530153565b9062ffffff811161018c5760ff81600392601d1a600185015380601e1a600285015316910153565b600080fd5b600360c09160ec815360896001820153602760028201530153565b81906000396000fdfe62000000565bfe5b62000000620000007c010000000000000000000000000000000000000000000000000000000060003504632b68b9c6147f46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f65433147fabc5a6e5e5382747a356658e4038b20ca3422a2b81ab44fd6e725e9f1e4cf81954600114826000148282171684620000990157818316846200009f015760006000fd5b50505050565b7f3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db811154ff000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000137472782073637269707420726576657274656400000000000000000000000000";
    }

    /**
     * @notice Returns the code associated with a running quark for `msg.sender`
     * @dev This is generally expected to be used only by the Quark wallet itself
     *      in the constructor phase to get its code.
     */
    function readQuark() external view returns (bytes memory) {
        address quarkAddress = msg.sender;
        uint256 quarkSize = quarkSizes[quarkAddress];
        if (quarkSize == 0) {
            revert QuarkNotActive(quarkAddress);
        }

        bytes memory quark = new bytes(quarkSize);
        uint256 chunks = wordSize(quarkSize);
        for (uint256 i = 0; i < chunks; i++) {
            bytes32 chunk = quarkChunks[quarkAddress][i];
            assembly {
                // TODO: Is there an easy way to do this in Solidity?
                // Note: the last one can overrun the size, should we prevent that?
                mstore(add(quark, add(32, mul(i, 32))), chunk)
            }
        }
        return quark;
    }

    // Internal function for running a quark. This handles the `create2`, invoking the script,
    // and then calling `destruct` to clean it up. We attempt to revert on any failed step.
    function _runQuark(address account, bytes memory quarkCode, bytes memory quarkCalldata) internal override returns (bytes memory) {
        address quarkAddress = getQuarkAddress(account);

        // Ensure a quark isn't already running
        if (quarkSizes[quarkAddress] > 0) {
            revert QuarkAlreadyActive(quarkAddress);
        }

        // Stores the quark in storage so it can be loaded via `readQuark` in the `create2`
        // constructor code (see `./Quark.yul`).
        saveQuark(quarkAddress, quarkCode);

        // Appends the account to the init code (the argument). This is meant to be part
        // of the `create2` init code, so that we get a unique quark wallet per address.
        bytes memory initCode = abi.encodePacked(
            getQuarkInitCode(),
            abi.encode(account)
        );

        uint256 initCodeLen = initCode.length;

        // The call to `create2` that creates the (temporary) quark wallet.
        DestructableQuark quark;
        assembly {
            quark := create2(0, add(initCode, 32), initCodeLen, 0)
        }
        // Ensure that the wallet was created.
        if (uint160(address(quark)) == 0) {
            revert QuarkInitFailed(quarkAddress, true);
        }
        if (quarkAddress != address(quark)) {
            revert QuarkAddressMismatch(quarkAddress, address(quark));
        }

        // Double ensure it was created by making sure it has code associated with it.
        // TODO: Do we need this double check there's code here?
        uint256 quarkCodeLen;
        assembly {
            quarkCodeLen := extcodesize(quark)
        }
        if (quarkCodeLen == 0) {
            revert QuarkInitFailed(quarkAddress, false);
        }

        // Check either the magic incantation (0x303030505050) _or_ isQuarkScript()
        // The goal here is to make sure that the the script is safe, since the worst case
        // is that the script doesn't self destruct. The magic incantation informs the
        // Quark constructor to build a self destruct function, and the `isQuarkScript`
        // check tries its best to make sure the script was derived from `QuarkScript`.
        //
        // A script that doesn't self-destruct will permanently break an account,
        // and a malicious dApp could do this on purpose. It's really hard to find
        // a way to know if a contract has called `self destruct` so we could revert
        // otherwise.
        //
        // Also, this has the side-effect of making sure we haven't accepted a 0-length
        // quark code, which would upset the isQuarkActive checks.
        if ((quarkCode.length < 6
            || quarkCode[0] != 0x30
            || quarkCode[1] != 0x30
            || quarkCode[2] != 0x30
            || quarkCode[3] != 0x50
            || quarkCode[4] != 0x50
            || quarkCode[5] != 0x50)) {
            try QuarkScript(address(quark)).isQuarkScript() returns (bytes32 isQuarkScriptHash) {
                if (isQuarkScriptHash != 0x390752087e6ef3cd5b0a0dede313512f6e47c12ea2c3b1972f19911725227c3e) { // keccak("org.quark.isQuarkScript")
                    revert QuarkInvalid(quarkAddress, isQuarkScriptHash);
                }
            } catch {
                revert QuarkInvalid(quarkAddress, 0x0); // Call failed
            }
        }

        // Call into the new quark wallet with a (potentially empty) message to hit the fallback function.
        (bool callSuccess, bytes memory res) = address(quark).call{value: msg.value}(quarkCalldata);
        if (!callSuccess) {
            revert QuarkCallFailed(quarkAddress, res);
        }

        // Call into the quark wallet to hit the `destruct` function.
        // Note: while it looks like the wallet doesn't have a `destruct` function, it's
        //       surrupticiously added by the Quark constructor in its init code. See
        //       `./Quark.yul` for more information.

        // TOOD: Curious what the return value here is, since it destructs but
        //       returns "ok"
        quark.destruct();

        // Clear all of the quark data to recoup gas costs.
        clearQuark(quarkAddress);

        // We return the result from the call, but it's not particularly important.
        return res;
    }

    // Saves quark code for an quark address into storage. This is required
    // since we can't pass unique quark code in the `create2` constructor,
    // since it would end up at a different wallet address.
    function saveQuark(address quarkAddress, bytes memory quark) internal {
        uint256 quarkSize = quark.length;
        uint256 chunks = wordSize(quarkSize);
        for (uint256 i = 0; i < chunks; i++) {
            bytes32 chunk;
            assembly {
                // TODO: Is there an easy way to do this in Solidity?
                chunk := mload(add(quark, add(32, mul(i, 32))))
            }
            quarkChunks[quarkAddress][i] = chunk;
        }
        quarkSizes[quarkAddress] = quarkSize;
    }

    // Clears quark data a) to save gas costs, and b) so another quark can
    // be run for the same quarkAddress in the future.
    function clearQuark(address quarkAddress) internal {
        uint256 quarkSize = quarkSizes[quarkAddress];
        if (quarkSize == 0) {
            revert QuarkNotActive(quarkAddress);
        }
        uint256 chunks = wordSize(quarkSize);
        for (uint256 i = 0; i < chunks; i++) {
            quarkChunks[quarkAddress][i] = 0;
        }
        quarkSizes[quarkAddress] = 0;
    }

    // wordSize returns the number of 32-byte words required to store a given value.
    // E.g. wordSize(0) = 0, wordSize(10) = 1, wordSize(32) = 1, wordSize(33) = 2
    function wordSize(uint256 x) internal pure returns (uint256) {
        uint256 r = x / 32;
        if (r * 32 < x) {
            return r + 1;
        } else {
            return r;
        }
    }
}