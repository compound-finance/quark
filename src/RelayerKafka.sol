// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Relayer.sol";
import "./QuarkScript.sol";

interface KafkaDestructableQuark {
    function destruct() external;
}

contract RelayerKafka is Relayer {
    error QuarkAlreadyActive(address quark);
    error QuarkNotActive(address quark);
    error QuarkInvalid(address quark, bytes32 isQuarkScriptHash);
    error QuarkInitFailed(address quark, bool create2Failed);
    error QuarkCallFailed(address quark, bytes error);
    error QuarkAddressMismatch(address expected, address created);
    error QuarkCodeSaveFailed(bytes initCode);
    error QuarkCodeSaveMismatch(bytes initCode, bytes quarkCode, address expected, address created);
    error QuarkTooLarge(uint256 sz);

    mapping(address => address) public quarkCodes;

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
        return hex"6040606b80601d600039338152602038601f190181830139016000f3fe6000604038603f190182396020816004818080518551632b68b9c6833560e01c14823314166065575b5063665f107960e01b82525af11560565780808051368280378136915af43d82803e156052573d90f35b3d90fd5b633c5bb1a760e21b8152600490fd5bff38602856";
    }

    function saveQuarkCode(bytes memory quarkCode) public returns (address) {
        /**
         * 0000    63XXXXXXXX  PUSH4 XXXXXXXX // code size
         * 0005    80          DUP1
         * 0006    600e        PUSH1 0x0e // this size
         * 0008    6000        PUSH1 0x00
         * 000a    39          CODECOPY
         * 000b    6000        PUSH1 0x00
         * 000d    F3          *RETURN
         */

        uint32 initCodeBaseSz = uint32(0x0e); // 0x630000000080600e6000396000f3
        if (quarkCode.length > type(uint32).max) {
            revert QuarkTooLarge(quarkCode.length);
        }
        uint32 quarkCodeSz = uint32(quarkCode.length);
        uint256 initCodeLen = initCodeBaseSz + quarkCodeSz;
        bytes memory initCode = new bytes(initCodeLen);

        assembly {
            function memcpy(dst, src, size) {
                for {} gt(size, 0) {}
                {
                    // Copy word
                    if gt(size, 31) { // ≥32
                        mstore(dst, mload(src))
                        dst := add(dst, 32)
                        src := add(src, 32)
                        size := sub(size, 32)
                        continue
                    }

                    // Copy byte
                    //
                    // Note: we can't use `mstore` here to store a full word since we could
                    // truncate past the end of the dst ptr.
                    mstore8(dst, and(mload(src), 0xff))
                    dst := add(dst, 1)
                    src := add(src, 1)
                    size := sub(size, 1)
                }
            }

            function copy4(dst, v) {
              if gt(v, 0xffffffff) {
                // operand too large
                revert(0, 0)
              }

              mstore8(add(dst, 0), byte(28, v))
              mstore8(add(dst, 1), byte(29, v))
              mstore8(add(dst, 2), byte(30, v))
              mstore8(add(dst, 3), byte(31, v))
            }

            let initCodeOffset := add(initCode, 0x20)
            mstore(initCodeOffset, 0x630000000080600e6000396000f3000000000000000000000000000000000000)
            memcpy(add(initCodeOffset, initCodeBaseSz), add(quarkCode, 0x20), quarkCodeSz)
            copy4(add(initCodeOffset, 1), quarkCodeSz)
        }

        address quarkCodeAddress = address(uint160(uint(
            keccak256(
                abi.encodePacked(
                    bytes1(0xff),
                    address(this),
                    uint256(0),
                    keccak256(initCode)
                )
            )))
        );

        uint256 quarkCodeAddressLen;
        assembly {
            quarkCodeAddressLen := extcodesize(quarkCodeAddress)
        }

        if (quarkCodeAddressLen == 0) {
            address quarkCodeCreateAddress;
            assembly {
                quarkCodeCreateAddress := create2(0, add(initCode, 32), initCodeLen, 0)
            }
            // Ensure that the wallet was created.
            if (uint160(address(quarkCodeCreateAddress)) == 0) {
                revert QuarkCodeSaveFailed(initCode);
            }
            if (quarkCodeCreateAddress != quarkCodeAddress) {
                revert QuarkCodeSaveMismatch(initCode, quarkCode, quarkCodeAddress, quarkCodeCreateAddress);
            }
        }

        return quarkCodeAddress;
    }

    /**
     * @notice Returns the code associated with a running quark for `msg.sender`
     * @dev This is generally expected to be used only by the Quark wallet itself
     *      in the constructor phase to get its code.
     */
    function readQuarkCode(address quarkCodeAddress) external view returns (bytes memory) {
        uint256 quarkCodeLen;
        assembly {
            quarkCodeLen := extcodesize(quarkCodeAddress)
        }

        bytes memory quarkCode = new bytes(quarkCodeLen);
        assembly {
            extcodecopy(quarkCodeAddress, add(quarkCode, 0x20), 0, quarkCodeLen)
        }

        return quarkCode;
    }

    // Saves quark code for an quark address into storage. This is required
    // since we can't pass unique quark code in the `create2` constructor,
    // since it would end up at a different wallet address.
    function saveQuark(address quarkAddress, bytes memory quarkCode) internal {
        quarkCodes[quarkAddress] = saveQuarkCode(quarkCode);
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
    function _runQuark(address account, bytes memory quarkCode, bytes memory quarkCalldata) internal override returns (bytes memory) {
        address quarkAddress = getQuarkAddress(account);

        // Ensure a quark isn't already running
        if (quarkCodes[quarkAddress] != address(0)) {
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
        KafkaDestructableQuark quark;

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

        // Call into the new quark wallet with a (potentially empty) message to hit the fallback function.
        (bool callSuccess, bytes memory res) = address(quark).call{value: msg.value}(quarkCalldata);
        if (!callSuccess) {
            revert QuarkCallFailed(quarkAddress, res);
        }

        // TOOD: Curious what the return value here is, since it destructs but
        //       returns "ok"
        quark.destruct();

        clearQuark(quarkAddress);

        // We return the result from the call, but it's not particularly important.
        return res;
    }
}
