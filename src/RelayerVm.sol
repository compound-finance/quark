// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Relayer.sol";
import "./QuarkVm.sol";
import "./QuarkVmWallet.sol";

contract RelayerVm is Relayer {
    error QuarkInitFailed(address quark, bool create2Failed);
    error QuarkCallFailed(address quark, bytes error);
    error QuarkAddressMismatch(address expected, address created);
    error FailedToDeployQuarkVm();

    QuarkVm immutable quarkVm;

    constructor() {
        quarkVm = new QuarkVm();
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
                            abi.encode(quarkVm),
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
        return type(QuarkVmWallet).creationCode;
    }

    // Internal function for running a quark. This handles the `create2`, invoking the script,
    // and then calling `destruct` to clean it up. We attempt to revert on any failed step.
    function _runQuark(address account, bytes memory quarkCode, bytes memory quarkCalldata) internal override returns (bytes memory) {
        address quarkAddress = getQuarkAddress(account);

        uint256 quarkCodeLen;
        assembly {
            quarkCodeLen := extcodesize(quarkAddress)
        }
        if (quarkCodeLen == 0) {
            // Appends the account to the init code (the argument). This is meant to be part
            // of the `create2` init code, so that we get a unique quark wallet per address.
            bytes memory initCode = abi.encodePacked(
                getQuarkInitCode(),
                abi.encode(quarkVm),
                abi.encode(account)
            );

            uint256 initCodeLen = initCode.length;

            // The call to `create2` that creates the (temporary) quark wallet.
            Quark quark;
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
        }

        QuarkVmWallet quarkVmWallet = QuarkVmWallet(payable(quarkAddress));

        quarkVmWallet.setQuark(quarkCode);

        // Call into the new quark wallet with a (potentially empty) message to hit the fallback function.
        (bool callSuccess, bytes memory res) = address(quarkVmWallet).call{value: msg.value}(quarkCalldata);
        if (!callSuccess) {
            revert QuarkCallFailed(quarkAddress, res);
        }

        quarkVmWallet.clearQuark();

        // We return the result from the first call, but it's not particularly important.
        return res;
    }
}
