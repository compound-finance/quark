// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract QuarkVm {

    struct VmCall {
        bytes vmCode;
        bytes vmCalldata;
    }

    function run(VmCall memory vmCall) external payable returns (bytes memory) {
        bytes memory vmCode = vmCall.vmCode;
        bytes memory vmCalldata = vmCall.vmCalldata;

        assembly {
            function allocate(size) -> ptr {
              /** Allocates memory in a safe way. Returns a pointer to it.
                */
                ptr := mload(0x40)
                if iszero(ptr) { ptr := 0x60 }
                mstore(0x40, add(ptr, size))
            }

            function allocate_unbounded() -> ptr {
                ptr := mload(0x40)
            }

            function get_op(vpc, vcodestart, vcodesize) -> op {
                // TODO: Make sure we don't overrun
                op := shr(248, mload(codeptr(vpc, vcodestart)))
                // log1(0, 0, add(shl(16, vpc), op))
            }

            function vpush(stk, v) -> nextstk {
                // TODO: Check the stack is full
                mstore(stk, v)
                // log2(0x2000, 0x60, stk, v)
                nextstk := add(stk, 0x20)
            }

            function vpop(stk) -> nextstk, v {
                // TODO: Check the stack is empty
                v := mload(sub(stk, 0x20))
                nextstk := sub(stk, 0x20)
            }

            function vset(stk, i, v) {
                // TODO: Check stack too deep
                let loc := sub(stk, mul(0x20, i))
                mstore(loc, v)
            }

            function vpeek(stk, i) -> v {
                // vpeek(stk, 0) -> stk[0] (head)
                // vpeek(stk, 1) -> stk[1], ...
                let loc := sub(stk, mul(0x20, add(1, i)))
                v := mload(loc)
            }

            function gte(a, b) -> r {
                r := iszero(lt(a, b))
            }

            function lte(a, b) -> r {
                r := iszero(gt(a, b))
            }

            function neq(a, b) -> r {
                r := iszero(eq(a, b))
            }

            function codeptr(offset, vcodestart) -> ptr {
                ptr := add(offset, vcodestart)
            }

            function calldataptr(offset, vcalldatastart) -> ptr {
                ptr := add(offset, vcalldatastart)
            }

            function memptr(offset, vmemstart) -> ptr {
                ptr := add(offset, vmemstart)
            }

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

            // Initialize stack pointer
            let stk_begin := allocate(0x2000)
            let stk := stk_begin
            let vmemstart := allocate_unbounded()

            let vcodesize := mload(vmCode)
            let vcodestart := add(vmCode, 0x20)
            let vcalldatasize := mload(vmCalldata)
            let vcalldatastart := add(vmCalldata, 0x20)

            // log3(vcodestart, vcodesize, 0xBEAD0000, vcodesize, vcodestart)
            // log3(vcalldatastart, vcalldatasize, 0xBEAD0001, vcalldatasize, vcalldatastart)

            for { let vpc := 0 } lt(vpc, vcodesize) { vpc := add(vpc, 1) }
            {
                let op := get_op(vpc, vcodestart, vcodesize)
                let stk_size := sub(stk, stk_begin)
                // log3(stk_begin, stk_size, 0xBEAD0002, vpc, op)

                // Special-case PUSH0-PUSH32
                if and(gte(op, 0x5f), lte(op, 0x7f)) {
                    // TODO: We should check for end of memory here as invalid
                    // TODO: Check we don't skip the bounds of codedata

                    // PUSH0-PUSH32
                    let v := shr(mul(8, sub(0x7f, op)), mload(add(add(vcodestart, vpc), 1)))
                    vpc := add(vpc, sub(op, 0x5f))
                    stk := vpush(stk, v)
                    continue
                }

                // Special-case DUP1-DUP16
                if and(gte(op, 0x80), lte(op, 0x8f)) {
                    // TODO: Check empty stack
                    let v := vpeek(stk, sub(op, 0x80))
                    stk := vpush(stk, v)
                    continue
                }

                // Special-case SWAP1-SWAP16
                if and(gte(op, 0x90), lte(op, 0x9f)) {
                    // TODO: Check empty stack
                    let n := sub(op, 0x80)
                    let head := vpeek(stk, 0)
                    let tail := vpeek(stk, n)
                    vset(stk, 0, tail)
                    vset(stk, n, head)
                    continue
                }

                switch op
                case 0x00 { // STOP
                    stop()
                }
                case 0x01 { // ADD
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, add(a, b))
                }
                case 0x02 { // MUL
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, mul(a, b))
                }
                case 0x03 { // SUB
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, sub(a, b))
                }
                case 0x04 { // DIV
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, div(a, b))
                }
                case 0x05 { // SDIV
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, sdiv(a, b))
                }
                case 0x06 { // MOD
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, mod(a, b))
                }
                case 0x07 { // SMOD
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, smod(a, b))
                }
                case 0x08 { // ADDMOD
                    let a, b, n
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk, n := vpop(stk)
                    stk := vpush(stk, addmod(a, b, n))
                }
                case 0x09 { // MULMOD
                    let a, b, n
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk, n := vpop(stk)
                    stk := vpush(stk, mulmod(a, b, n))
                }
                case 0x0a { // EXP
                    let a, expo
                    stk, a := vpop(stk)
                    stk, expo := vpop(stk)
                    stk := vpush(stk, exp(a, expo))
                }
                case 0x0b { // SIGNEXTEND
                    let b, x
                    stk, b := vpop(stk)
                    stk, x := vpop(stk)
                    stk := vpush(stk, signextend(b, x))
                }
                case 0x10 { // LT
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, lt(a, b))
                }
                case 0x11 { // GT
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, gt(a, b))
                }
                case 0x12 { // SLT
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, slt(a, b))
                }
                case 0x13 { // SGT
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, sgt(a, b))
                }
                case 0x14 { // EQ
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, eq(a, b))
                }
                case 0x15 { // ISZERO
                    let a
                    stk, a := vpop(stk)
                    stk := vpush(stk, iszero(a))
                }
                case 0x16 { // AND
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, and(a, b))
                }
                case 0x17 { // OR
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, or(a, b))
                }
                case 0x18 { // XOR
                    let a, b
                    stk, a := vpop(stk)
                    stk, b := vpop(stk)
                    stk := vpush(stk, xor(a, b))
                }
                case 0x19 { // NOT
                    let a
                    stk, a := vpop(stk)
                    stk := vpush(stk, not(a))
                }
                case 0x1a { // BYTE
                    let i, x
                    stk, i := vpop(stk)
                    stk, x := vpop(stk)
                    stk := vpush(stk, byte(i, x))
                }
                case 0x1b { // SHL
                    let shift, value
                    stk, shift := vpop(stk)
                    stk, value := vpop(stk)
                    stk := vpush(stk, shl(shift, value))
                }
                case 0x1c { // SHR
                    let shift, value
                    stk, shift := vpop(stk)
                    stk, value := vpop(stk)
                    stk := vpush(stk, shr(shift, value))
                }
                case 0x1d { // SAR
                    let shift, value
                    stk, shift := vpop(stk)
                    stk, value := vpop(stk)
                    stk := vpush(stk, sar(shift, value))
                }
                case 0x20 { // SHA3
                    let offset, size
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    let hash := keccak256(memptr(offset, vmemstart), size)
                    stk := vpush(stk, hash)
                }
                case 0x30 { // ADDRESS
                    stk := vpush(stk, address())
                }
                case 0x31 { // BALANCE
                    let addr
                    stk, addr := vpop(stk)
                    stk := vpush(stk, balance(addr))
                }
                case 0x32 { // ORIGIN
                    stk := vpush(stk, origin())
                }
                case 0x33 { // CALLER
                    stk := vpush(stk, caller())
                }
                case 0x34 { // CALLVALUE
                    stk := vpush(stk, callvalue())
                }
                case 0x35 { // CALLDATALOAD
                    let i, lastbyte
                    stk, i := vpop(stk)
                    lastbyte := add(i, 32)
                    let v := mload(add(i, vcalldatastart))
                    if gt(lastbyte, vcalldatasize) {
                        // e.g. lastbyte = 55, vcalldataended at 50, so we want to make out the last 5 bytes or
                        // 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000000000
                        let mask_len := sub(lastbyte, vcalldatasize)

                        // We'll shift right and then shift left to clear out the low bits
                        let mask := shl(mask_len, shr(mask_len, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff))
                        v := and(v, mask)
                    }
                    stk := vpush(stk, v)
                }
                case 0x36 { // CALLDATASIZE
                    stk := vpush(stk, vcalldatasize)
                }
                case 0x37 { // CALLDATACOPY
                    let dstoffset, offset, size
                    stk, dstoffset := vpop(stk)
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)

                    if gt(add(offset, size), vcalldatasize) {
                        revert(0, 0) // out of bounds
                    }
                    memcpy(memptr(dstoffset, vmemstart), calldataptr(offset, vcalldatastart), size)
                }
                case 0x38 { // CODESIZE
                    stk := vpush(stk, vcodesize)
                }
                case 0x39 { // CODECOPY
                    let dstoffset, offset, size
                    stk, dstoffset := vpop(stk)
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)

                    if gt(add(offset, size), vcodesize) {
                        revert(0, 0) // out of bounds
                    }
                    memcpy(memptr(dstoffset, vmemstart), calldataptr(offset, vcodesize), size)
                }
                case 0x3a { // GASPRICE
                    stk := vpush(stk, gasprice())
                }
                case 0x3b { // EXTCODESIZE
                    let addr, dstoffset, offset, size
                    stk, addr := vpop(stk)
                    stk := vpush(stk, extcodesize(addr))
                }
                case 0x3c { // EXTCODECOPY
                    let addr, dstoffset, offset, size
                    stk, addr := vpop(stk)
                    stk, dstoffset := vpop(stk)
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    extcodecopy(addr, dstoffset, memptr(offset, vmemstart), size)
                }
                case 0x3d { // RETURNDATASIZE
                    stk := vpush(stk, returndatasize())
                }
                case 0x3e { // RETURNDATACOPY
                    let dstoffset, offset, size
                    stk, dstoffset := vpop(stk)
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    returndatacopy(dstoffset, memptr(offset, vmemstart), size)
                }
                case 0x3f { // EXTCODEHASH
                    let addr
                    stk, addr := vpop(stk)
                    stk := vpush(stk, extcodehash(addr))
                }
                case 0x40 { // BLOCKHASH
                    let blocknumber
                    stk, blocknumber := vpop(stk)
                    stk := vpush(stk, blockhash(blocknumber))
                }
                case 0x41 { // COINBASE
                    stk := vpush(stk, coinbase())
                }
                case 0x42 { // TIMESTAMP
                    stk := vpush(stk, timestamp())
                }
                case 0x43 { // NUMBER
                    stk := vpush(stk, number())
                }
                case 0x44 { // DIFFICULTY
                    // TODO: Disallowed?
                    stk := vpush(stk, difficulty())
                }
                case 0x45 { // GASLIMIT
                    stk := vpush(stk, gaslimit())
                }
                case 0x46 { // CHAINID
                    stk := vpush(stk, chainid())
                }
                case 0x47 { // SELFBALANCE
                    stk := vpush(stk, selfbalance())
                }
                case 0x48 { // BASEFEE
                    stk := vpush(stk, basefee())
                }
                case 0x50 { // POP
                    let unused
                    stk, unused := vpop(stk)
                }
                case 0x51 { // MLOAD
                    let offset
                    stk, offset := vpop(stk)
                    let v := mload(memptr(offset, vmemstart))
                    stk := vpush(stk, v)
                }
                case 0x52 { // MSTORE
                    let offset, v
                    stk, offset := vpop(stk)
                    stk, v := vpop(stk)
                    mstore(memptr(offset, vmemstart), v)
                }
                case 0x53 { // MSTORE8
                    let offset, v
                    stk, offset := vpop(stk)
                    stk, v := vpop(stk)
                    mstore8(memptr(offset, vmemstart), and(v, 0xff))
                }
                case 0x54 { // SLOAD
                    let key
                    stk, key := vpop(stk)
                    stk := vpush(stk, sload(key))
                }
                case 0x55 { // SSTORE
                    let key, value
                    stk, key := vpop(stk)
                    stk, value := vpop(stk)
                    sstore(key, value)
                }
                case 0x56 { // JUMP
                    let dst
                    stk, dst := vpop(stk)
                    if neq(get_op(dst, vcodestart, vcodesize), 0x5B) { // JUMPDEST
                        // Provide a better way to sim a jump failure
                        revert(0, 0)
                    }
                    vpc := add(dst, 1)
                }
                case 0x57 { // JUMPI
                    let dst, cond
                    stk, dst := vpop(stk)
                    stk, cond := vpop(stk)
                    let dstop := get_op(dst, vcodestart, vcodesize)
                    // log3(0, 0, cond, dst, dstop)
                    if neq(dstop, 0x5B) { // JUMPDEST
                        // Provide a better way to sim a jump failure
                        revert(0, 0)
                    }
                    if gt(cond, 0) {
                        vpc := add(dst, 1)
                    }
                }
                case 0x58 { // PC
                    // TODO: Make sure this isn't off by one?
                    stk := vpush(stk, vpc)
                }
                case 0x59 { // MSIZE
                    // let msz := msize()
                    let msz := 0 // TODO: Simulate
                    if gte(msz, 0x4000) {
                        stk := vpush(stk, sub(msz, 0x4000))
                        continue
                    }
                    // else [memory is empty]
                    stk := vpush(stk, 0)
                    continue
                }
                case 0x5a { // GAS
                    stk := vpush(stk, gas())
                }
                case 0x5b { // JUMPDEST
                    // nop
                }
                case 0xa0 { // LOG0
                    let offset, size
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    log0(memptr(offset, vmemstart), size) // TODO: Double check this
                }
                case 0xa1 { // LOG1
                    let offset, size, topic0
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    stk, topic0 := vpop(stk)
                    log1(memptr(offset, vmemstart), size, topic0)
                }
                case 0xa2 { // LOG2
                    let offset, size, topic0, topic1
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    stk, topic0 := vpop(stk)
                    stk, topic1 := vpop(stk)
                    log2(memptr(offset, vmemstart), size, topic0, topic1)
                }
                case 0xa3 { // LOG3
                    let offset, size, topic0, topic1, topic2
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    stk, topic0 := vpop(stk)
                    stk, topic1 := vpop(stk)
                    stk, topic2 := vpop(stk)
                    log3(memptr(offset, vmemstart), size, topic0, topic1, topic2)
                }
                case 0xa4 { // LOG4
                    let offset, size, topic0, topic1, topic2, topic3
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    stk, topic0 := vpop(stk)
                    stk, topic1 := vpop(stk)
                    stk, topic2 := vpop(stk)
                    stk, topic3 := vpop(stk)
                    log4(memptr(offset, vmemstart), size, topic0, topic1, topic2, topic3)
                }
                case 0xf0 { // CREATE
                    let value, offset, size
                    stk, value := vpop(stk)
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    let r := create(value, memptr(offset, vmemstart), size)
                    stk := vpush(stk, r)
                }
                case 0xf1 { // CALL
                    let gasv, addr, value, argsoffset, argssize, retoffset, retsize

                    stk, gasv := vpop(stk)
                    stk, addr := vpop(stk)
                    stk, value := vpop(stk)
                    stk, argsoffset := vpop(stk)
                    stk, argssize := vpop(stk)
                    stk, retoffset := vpop(stk)
                    stk, retsize := vpop(stk)
                    // log3(0, 0, gasv, addr, value)
                    // log2(
                    //     memptr(argsoffset, vmemstart),
                    //     argssize,
                    //     argsoffset,
                    //     argssize
                    // )
                    // log2(0, 0, retoffset, retsize)
                    let success := call(
                        gasv,
                        addr,
                        value,
                        memptr(argsoffset, vmemstart),
                        argssize,
                        memptr(retoffset, vmemstart),
                        retsize
                    )
                    stk := vpush(stk, success)
                }
                case 0xf2 { // CALLCODE
                    let gasv, addr, value, argsoffset, argssize, retoffset, retsize

                    stk, gasv := vpop(stk)
                    stk, addr := vpop(stk)
                    stk, value := vpop(stk)
                    stk, argsoffset := vpop(stk)
                    stk, argssize := vpop(stk)
                    stk, retoffset := vpop(stk)
                    stk, retsize := vpop(stk)
                    let success := callcode(
                        gasv,
                        addr,
                        value,
                        memptr(argsoffset, vmemstart),
                        argssize,
                        memptr(retoffset, vmemstart),
                        retsize
                    )
                    stk := vpush(stk, success)
                }
                case 0xf3 { // RETURN
                    let offset, size
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    let memoffset := sub(memptr(offset, vmemstart), 0x20) // This can truncate other memory, but luckily, we're done now.
                    mstore(memoffset, size)
                    // log3(memoffset, add(size, 0x20), 0xBEAD0099, offset, size)
                    return(memoffset, add(size, 0x20)) // Change this to be length-prefixed
                }
                case 0xf4 { // DELEGATECALL
                    let gasv, addr, argsoffset, argssize, retoffset, retsize

                    stk, gasv := vpop(stk)
                    stk, addr := vpop(stk)
                    stk, argsoffset := vpop(stk)
                    stk, argssize := vpop(stk)
                    stk, retoffset := vpop(stk)
                    stk, retsize := vpop(stk)
                    let success := delegatecall(
                        gasv,
                        addr,
                        memptr(argsoffset, vmemstart),
                        argssize,
                        memptr(retoffset, vmemstart),
                        retsize
                    )
                    stk := vpush(stk, success)
                }
                case 0xf5 { // CREATE2
                    let value, offset, size, salt
                    stk, value := vpop(stk)
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    stk, salt := vpop(stk)
                    let r := create2(value, memptr(offset, vmemstart), size, salt)
                    stk := vpush(stk, r)
                }
                case 0xfa { // STATICCALL
                    let gasv, addr, argsoffset, argssize, retoffset, retsize

                    stk, gasv := vpop(stk)
                    stk, addr := vpop(stk)
                    stk, argsoffset := vpop(stk)
                    stk, argssize := vpop(stk)
                    stk, retoffset := vpop(stk)
                    stk, retsize := vpop(stk)
                    let success := staticcall(
                        gasv,
                        addr,
                        memptr(argsoffset, vmemstart),
                        argssize,
                        memptr(retoffset, vmemstart),
                        retsize
                    )
                    stk := vpush(stk, success)
                }
                case 0xfd { // REVERT
                    let offset, size
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    revert(memptr(offset, vmemstart), size)
                }
                case 0xfe { // REVERT
                    // verbatim_0i_0o("fe") // Do we want to invalid ourselves for real?
                }
                case 0xff { // SELFDESTRUCT
                    let recipient
                    stk, recipient := vpop(stk)
                    revert(0, 0)
                    // TODO: sd? this is breaking compilation
                    // selfdestruct(recipient)
                }
                default {
                    // Unknown opcode
                    revert(0, 0)
                }
            }

            // Program ended without returning
            revert(0, 0)
        }
    }
}
