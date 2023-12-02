// Note: outputs to 241 bytes

object "ProxyDirect_48" {
    code {
        {
            /// @src 0:66:1588  "contract ProxyDirect {..."
            let _1 := memoryguard(0xe0)
            if callvalue() { revert(0, 0) }
            let programSize := datasize("ProxyDirect_48")
            let argSize := sub(codesize(), programSize)
            let newFreePtr := add(_1, and(add(argSize, 31), not(31)))
            if or(gt(newFreePtr, sub(shl(64, 1), 1)), lt(newFreePtr, _1))
            {
                mstore(/** @src -1:-1:-1 */ 0, /** @src 0:66:1588  "contract ProxyDirect {..." */ shl(224, 0x4e487b71))
                mstore(4, 0x41)
                revert(/** @src -1:-1:-1 */ 0, /** @src 0:66:1588  "contract ProxyDirect {..." */ 0x24)
            }
            mstore(64, newFreePtr)
            codecopy(_1, programSize, argSize)
            if slt(sub(add(_1, argSize), _1), 96)
            {
                revert(/** @src -1:-1:-1 */ 0, 0)
            }
            /// @src 0:66:1588  "contract ProxyDirect {..."
            let value0 := abi_decode_address_fromMemory(_1)
            let value1 := abi_decode_address_fromMemory(add(_1, 32))
            let value2 := abi_decode_address_fromMemory(add(_1, 64))
            /// @src 0:851:867  "signer = signer_"
            mstore(128, value1)
            /// @src 0:877:897  "executor = executor_"
            mstore(160, value2)
            /// @src 0:907:945  "walletImplementation = implementation_"
            mstore(192, value0)
            /// @src 0:66:1588  "contract ProxyDirect {..."
            let _2 := mload(64)
            let _3 := datasize("ProxyDirect_48_deployed")
            codecopy(_2, dataoffset("ProxyDirect_48_deployed"), _3)
            setimmutable(_2, "4", mload(/** @src 0:851:867  "signer = signer_" */ 128))
            /// @src 0:66:1588  "contract ProxyDirect {..."
            setimmutable(_2, "7", mload(/** @src 0:877:897  "executor = executor_" */ 160))
            /// @src 0:66:1588  "contract ProxyDirect {..."
            setimmutable(_2, "10", mload(/** @src 0:907:945  "walletImplementation = implementation_" */ 192))
            /// @src 0:66:1588  "contract ProxyDirect {..."
            return(_2, _3)
        }
        function abi_decode_address_fromMemory(offset) -> value
        {
            value := mload(offset)
            if iszero(eq(value, and(value, sub(shl(160, 1), 1)))) { revert(0, 0) }
        }
    }
    /// @use-src 0:"src-proxy/ProxyDirect.sol"
    object "ProxyDirect_48_deployed" {
        code {
            {
                /// @src 0:66:1588  "contract ProxyDirect {..."
                mstore(64, 128)
                if iszero(lt(calldatasize(), 4))
                {
                    let _1 := 0
                    switch shr(224, calldataload(_1))
                    case 0x238ac933 {
                        if callvalue() { revert(_1, _1) }
                        if slt(add(calldatasize(), not(3)), _1) { revert(_1, _1) }
                        mstore(128, and(/** @src 0:208:239  "address public immutable signer" */ loadimmutable("4"), /** @src 0:66:1588  "contract ProxyDirect {..." */ sub(shl(160, 1), 1)))
                        return(128, 32)
                    }
                    case 0xc34c08e5 {
                        if callvalue() { revert(_1, _1) }
                        if slt(add(calldatasize(), not(3)), _1) { revert(_1, _1) }
                        let memPos := mload(64)
                        mstore(memPos, and(/** @src 0:368:401  "address public immutable executor" */ loadimmutable("7"), /** @src 0:66:1588  "contract ProxyDirect {..." */ sub(shl(160, 1), 1)))
                        return(memPos, 32)
                    }
                }
                /// @ast-id 47 @src 0:1043:1586  "fallback(bytes calldata /* data *\/) external payable returns (bytes memory) {..."
                /** @ast-id 47 */ /** @ast-id 47 */ pop(/** @ast-id 47 */ /** @ast-id 47 */ fun())
            }
            /// @ast-id 47
            function fun() -> var_mpos
            {
                /// @src 0:1105:1117  "bytes memory"
                var_mpos := /** @src 0:66:1588  "contract ProxyDirect {..." */ 96
                /// @src 0:1191:1580  "assembly {..."
                let _1 := 0
                calldatacopy(_1, _1, calldatasize())
                let usr$succ := delegatecall(gas(), /** @src 0:1161:1181  "walletImplementation" */ loadimmutable("10"), /** @src 0:1191:1580  "assembly {..." */ _1, calldatasize(), _1, _1)
                let usr$retSz := returndatasize()
                returndatacopy(_1, _1, usr$retSz)
                if usr$succ { return(_1, usr$retSz) }
                revert(_1, usr$retSz)
            }
        }
        data ".metadata" hex""
    }
}