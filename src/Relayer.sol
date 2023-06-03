// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface Quark {
    function destruct() external;
    fallback() external;
}

contract Relayer {
    error QuarkAlreadyActive();
    error QuarkNotActive();
    error QuarkInvalid();
    error QuarkInitFailed(bool create2Failed);
    error QuarkCallFailed(bytes error);
    error BadSignatory();
    error InvalidValueS();
    error InvalidValueV();
    error SignatureExpired();
    error NonceReplay();
    error NonceMissingReq(uint32 req);

    mapping(address => uint256) public quarkSizes;
    mapping(address => mapping(uint256 => bytes32)) quarkChunks;
    mapping(address => mapping(uint256 => uint256)) nonces;

    /// @notice The major version of this contract
    string public constant version = "0";

    /** Internal constants **/

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 internal constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev The EIP-712 typehash for runTrxScript
    bytes32 internal constant TRX_SCRIPT_TYPEHASH = keccak256("TrxScript(address account,uint32 nonce,uint32[] reqs,bytes trxScript,uint256 expiry)");

    /// @dev See https://ethereum.github.io/yellowpaper/paper.pdf #307)
    uint internal constant MAX_VALID_ECDSA_S = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    // Sets a nonce if it's unset, otherwise reverts with `NonceReplay`.
    function trySetNonce(address account, uint32 nonce) internal {
        uint32 nonceIndex = nonce / 256;
        uint32 nonceOffset = nonce - ( nonceIndex * 256 );
        uint256 nonceBit = (2 << nonceOffset);

        uint256 nonceChunk = nonces[account][uint256(nonceIndex)];
        if (nonceChunk & nonceBit > 0) {
            revert NonceReplay();
        }
        nonces[account][nonceIndex] |= nonceBit;
    }

    // Returns whether a given nonce has been committed already.
    // TODO: We could make this a lot more efficient if we bulk nonces together
    function getNonce(address account, uint32 nonce) internal view returns (bool) {
        uint32 nonceIndex = nonce / 256;
        uint32 nonceOffset = nonce - ( nonceIndex * 256 );
        uint256 nonceBit = (2 << nonceOffset);

        uint256 nonceChunk = nonces[account][uint256(nonceIndex)];
        return nonceChunk & nonceBit > 0;
    }

    // Ensures that all reqs for a given script have been previously committed.
    // TODO: We could make this a lot more efficient if we bulk nonces together
    function checkReqs(address account, uint32[] memory reqs) internal view {
        for (uint256 i = 0; i < reqs.length; i++) {
            if (!getNonce(account, reqs[i])) {
                revert NonceMissingReq(reqs[i]);
            }
        }
    }

    /**
     * @notice Runs a quark script
     * @param account The owner account (that is, EOA, not the quark address)
     * @param nonce The next expected nonce value for the signatory
     * @param reqs List of previous nonces that must first be incorporated
     * @param expiry The expiration time of this
     * @param trxScript The transaction scrip to run
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function runTrxScript(
        address account,
        uint32 nonce,
        uint32[] calldata reqs,
        bytes calldata trxScript,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes memory) {
        if (uint256(s) > MAX_VALID_ECDSA_S) revert InvalidValueS();
        // v ∈ {27, 28} (source: https://ethereum.github.io/yellowpaper/paper.pdf #308)
        if (v != 27 && v != 28) revert InvalidValueV();
        bytes32 domainSeparator = DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(abi.encode(TRX_SCRIPT_TYPEHASH, account, nonce, keccak256(abi.encode(reqs)), keccak256(trxScript), expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        if (signatory == address(0)) revert BadSignatory();
        if (account != signatory) revert BadSignatory();
        if (block.timestamp >= expiry) revert SignatureExpired();

        checkReqs(account, reqs);
        trySetNonce(account, nonce);

        return runQuark_(account, trxScript);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("Quark")), keccak256(bytes(version)), block.chainid, address(this)));
    }

    /**
     * @notice Helper function to return a quark address for a given account.
     */
    function getQuarkAddress(address account) external view returns (address) {
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
    function getQuarkInitCode() public pure returns (bytes memory) {
        return hex"5f80600461000b6100f1565b61001481610188565b82335af1156100e7573d6083810190603f199060c38282016100358561012b565b93816040863e65303030505050855160d01c036100dd576100969261005861010e565b60206103348239519460066101ab8839610076603e1982018861015c565b8601916101b19083013961008d603d198201610147565b6039190161015c565b7f3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db811155337f46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f655f35b60606102746101a3565b60606102d46101a3565b604051908115610105575b60048201604052565b606091506100fc565b604051908115610122575b60208201604052565b60609150610119565b9060405191821561013e575b8201604052565b60609250610137565b60036005915f60018201535f60028201530153565b9062ffffff81116101845760ff81600392601d1a600185015380601e1a600285015316910153565b5f80fd5b600360c09160ec815360896001820153602760028201530153565b81905f395ffdfe62000000565bfe5b62000000620000007c010000000000000000000000000000000000000000000000000000000060003504632b68b9c6147f46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f65433147fabc5a6e5e5382747a356658e4038b20ca3422a2b81ab44fd6e725e9f1e4cf81954600114826000148282171684620000990157818316846200009f015760006000fd5b50505050565b7f3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db811154ff000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000127472782073637269707420696e76616c69640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000137472782073637269707420726576657274656400000000000000000000000000";
    }

    /**
     * @notice Returns the code associated with a running quark for `msg.sender`
     * @dev This is generally expected to be used only by the Quark wallet itself
     *      in the constructor phase to get its code.
     */
    function readQuark() external view returns (bytes memory) {
        address account = msg.sender;
        uint256 quarkSize = quarkSizes[account];
        if (quarkSize == 0) {
            revert QuarkNotActive();
        }
        
        bytes memory quark = new bytes(quarkSize);
        uint256 chunks = wordSize(quarkSize);
        for (uint256 i = 0; i < chunks; i++) {
            bytes32 chunk = quarkChunks[account][i];
            assembly {
                // TODO: Is there an easy way to do this in Solidity?
                // Note: the last one can overrun the size, should we prevent that?
                mstore(add(quark, add(32, mul(i, 32))), chunk)
            }
        }
        return quark;
    }

    /**
     * Run a quark script from a given account. Note: can also use fallback, which is
     * an alias to this function.
     */
    function runQuark(bytes memory quarkCode) external payable returns (bytes memory) {
        return _runQuark(msg.sender, quarkCode);
    }

    // Internal function for running a quark. This handles the `create2`, invoking the script,
    // and then calling `destruct` to clean it up. We attempt to revert on any failed step.
    function _runQuark(address account, bytes memory quarkCode) internal returns (bytes memory) {
        // Ensure a quark isn't already running
        if (quarkSize[account] > 0) {
            revert QuarkAlreadyActive();
        }

        // Check the magic incantation (0x303030606060).
        // This has the side-effect of making sure we don't accept 0-length quark code.
        if (quarkCode.length < 6
            || quarkCode[0] != 0x30
            || quarkCode[1] != 0x30
            || quarkCode[2] != 0x30
            || quarkCode[3] != 0x60
            || quarkCode[4] != 0x60
            || quarkCode[5] != 0x60) {
            revert QuarkInvalid();
        }

        // Stores the quark in storage so it can be loaded via `readQuark` in the `create2`
        // constructor code (see `./Quark.yul`).
        saveQuark(account, quarkCode);

        // Appends the account to the init code (the argument). This is meant to be part
        // of the `create2` init code, so that we get a unique quark wallet per address.
        bytes memory initCode = abi.encodePacked(
            getQuarkInitCode(),
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
            revert QuarkInitFailed(true);
        }

        // Double ensure it was created by making sure it has code associated with it.
        // TODO: Do we need this double check there's code here?
        uint256 quarkCodeLen;
        assembly {
            quarkCodeLen := extcodesize(quark)
        }
        if (quarkCodeLen == 0) {
            revert QuarkInitFailed(false);
        }

        // Call into the new quark wallet with an empty message to hit the fallback function.
        (bool callSuccess, bytes memory res) = address(quark).call{value: msg.value}(hex"");
        if (!callSuccess) {
            revert QuarkCallFailed(res);
        }

        // Call into the quark wallet to hit the `destruct` function.
        // Note: while it looks like the wallet doesn't have a `destruct` function, it's
        //       surrupticiously added by the Quark constructor in its init code. See
        //       `./Quark.yul` for more information.
        quark.destruct();

        // Clear all of the quark data to recoup gas costs.
        clearQuark(account);

        // We return the result from the first call, but it's not particularly important.
        return res;
    }

    /***
     * @notice Runs a given quark script, if valid, from the current sender.
     */
    fallback(bytes calldata quarkCode) external payable returns (bytes memory) {
        return runQuark_(msg.sender, quarkCode);
    }

    // Saves quark code for an account into storage. This is required since
    // we can't pass unique quark code in the `create2` constructor, since
    // it would end up at a different wallet address.
    function saveQuark(address account, bytes memory quark) internal {
        uint256 quarkSize = quark.length;
        uint256 chunks = wordSize(quarkSize);
        for (uint256 i = 0; i < chunks; i++) {
            bytes32 chunk;
            assembly {
                // TODO: Is there an easy way to do this in Solidity?
                chunk := mload(add(quark, add(32, mul(i, 32))))
            }
            quarkChunks[account][i] = chunk;
        }
        quarkSizes[account] = quarkSize;
    }

    // Clears quark data a) to save gas costs, and b) so another quark can
    // be run for the same account in the future.
    function clearQuark(address account) internal {
        uint256 chunks = wordSize(quarkSize);
        for (uint256 i = 0; i < chunks; i++) {
            quarkChunks[account][i] = 0;
        }
        quarkSizes[account] = 0;
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
