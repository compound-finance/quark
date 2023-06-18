// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./QuarkScript.sol";

struct TrxScript {
    address account;
    uint32 nonce;
    uint32[] reqs;
    bytes trxScript;
    bytes trxCalldata;
    uint256 expiry;
}

abstract contract Relayer {
    error BadSignatory();
    error InvalidValueS();
    error InvalidValueV();
    error SignatureExpired();
    error NonceReplay(uint256 nonce);
    error NonceMissingReq(uint32 req);

    mapping(address => mapping(uint256 => uint256)) nonces;

    /// @notice The major version of this contract
    string public constant version = "0";

    /** Internal constants **/

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 internal constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev The EIP-712 typehash for runTrxScript
    bytes32 internal constant TRX_SCRIPT_TYPEHASH = keccak256("TrxScript(address account,uint32 nonce,uint32[] reqs,bytes trxScript,bytes trxCalldata,uint256 expiry)");

    /// @dev See https://ethereum.github.io/yellowpaper/paper.pdf #307)
    uint internal constant MAX_VALID_ECDSA_S = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    // Sets a nonce if it's unset, otherwise reverts with `NonceReplay`.
    function trySetNonce(address account, uint32 nonce) internal {
        uint32 nonceIndex = nonce / 256;
        uint32 nonceOffset = nonce - ( nonceIndex * 256 );
        uint256 nonceBit = (2 << nonceOffset);

        uint256 nonceChunk = nonces[account][uint256(nonceIndex)];
        if (nonceChunk & nonceBit > 0) {
            revert NonceReplay(nonce);
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

    function checkSignature(
        address account,
        uint32 nonce,
        uint32[] calldata reqs,
        bytes calldata trxScript,
        bytes calldata trxCalldata,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view {
        if (uint256(s) > MAX_VALID_ECDSA_S) revert InvalidValueS();
        // v ∈ {27, 28} (source: https://ethereum.github.io/yellowpaper/paper.pdf #308)
        if (v != 27 && v != 28) revert InvalidValueV();
        bytes32 structHash = keccak256(abi.encode(TRX_SCRIPT_TYPEHASH, account, nonce, keccak256(abi.encodePacked(reqs)), keccak256(trxScript), keccak256(trxCalldata), expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        address signatory = ecrecover(digest, v, r, s);
        if (signatory == address(0)) revert BadSignatory();
        if (account != signatory) revert BadSignatory();
    }

    /**
     * @notice Runs a quark script
     * @param account The owner account (that is, EOA, not the quark address)
     * @param nonce The next expected nonce value for the signatory
     * @param reqs List of previous nonces that must first be incorporated
     * @param expiry The expiration time of this
     * @param trxScript The transaction script to run
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function runTrxScript(
        address account,
        uint32 nonce,
        uint32[] calldata reqs,
        bytes calldata trxScript,
        bytes calldata trxCalldata,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes memory) {
        checkSignature(account, nonce, reqs, trxScript, trxCalldata, expiry, v, r, s);
        if (block.timestamp >= expiry) revert SignatureExpired();

        checkReqs(account, reqs);
        trySetNonce(account, nonce);

        return _runQuark(account, trxScript, trxCalldata);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Quark"), keccak256(bytes(version)), block.chainid, address(this)));
    }

    /**
     * @notice Helper function to return a quark address for a given account.
     */
    function getQuarkAddress(address account) public virtual view returns (address);

    /**
     * @notice The init code for a Quark wallet.
     * @dev The actual init code for a Quark wallet, passed to `create2`. This is
     *      the yul output from `./Quark.yul`, but it's impossible to reference
     *      a yul object in Solidity, so we do a two phase compile where we
     *      build that code, take the outputed bytecode and paste it in here.
     */
    function getQuarkInitCode() public virtual pure returns (bytes memory);

    /**
     * Run a quark script from a given account. Note: can also use fallback, which is
     * an alias to this function.
     */
    function runQuark(bytes calldata quarkCode) external payable returns (bytes memory) {
        return _runQuark(msg.sender, quarkCode, hex"");
    }

    /**
     * Run a quark script from a given account. Note: can also use fallback, which is
     * an alias to this function. This variant allows you to pass in data that will
     * be passed to the Quark script on its invocation.
     */
    function runQuark(bytes calldata quarkCode, bytes calldata quarkCalldata) external payable returns (bytes memory) {
        return _runQuark(msg.sender, quarkCode, quarkCalldata);
    }

    // Internal function for running a quark. This handles the `create2`, invoking the script,
    // and then calling `destruct` to clean it up. We attempt to revert on any failed step.
    function _runQuark(address account, bytes memory quarkCode, bytes memory quarkCalldata) internal virtual returns (bytes memory);

    /***
     * @notice Runs a given quark script, if valid, from the current sender.
     */
    fallback(bytes calldata quarkCode) external payable returns (bytes memory) {
        return _runQuark(msg.sender, quarkCode, hex"");
    }

    /***
     * @notice Revert given empty call.
     */
    receive() external payable {
        revert();
    }
}
