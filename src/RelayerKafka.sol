// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Relayer.sol";
import "./QuarkScript.sol";
import "./CodeJar.sol";

interface KafkaDestructableQuark {
    function destruct() external;
}

contract RelayerKafka is Relayer {
    CodeJar public immutable codeJar;

    error QuarkAlreadyActive(address quark);
    error QuarkNotActive(address quark);
    error QuarkInvalid(address quark, bytes32 isQuarkScriptHash);
    error QuarkInitFailed(address quark, bool create2Failed);
    error QuarkCallFailed(address quark, bytes error);
    error QuarkAddressMismatch(address expected, address created);

    mapping(address => address) public quarkCodes;

    constructor() {
        address codeJar_ = abi.decode(msg.data, (address));
        if (codeJar_ == address(0)) {
            codeJar_ = address(new CodeJar());
        }
        codeJar = CodeJar(codeJar_);
    }

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
        return hex"604060b180610066600039338152602081016020601f193801823951337f46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6557f3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db811155016000f3fe6000604038603f190182396020816004818080518551632b68b9c6833560e01c14823314166065575b5063665f107960e01b82525af11560565780808051368280378136915af43d82803e156052573d90f35b3d90fd5b633c5bb1a760e21b8152600490fd5b827f46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f655827f3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db811155ff38602856";
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
