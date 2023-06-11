// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract QuarkVm {
    event CallQuarkScript(bytes vmCode, bytes vmCalldata);

    struct VmCall {
        bytes vmCode;
        bytes vmCalldata;
    }

    function run(VmCall memory vmCall) external payable {
        bytes memory vmCode = vmCall.vmCode;
        bytes memory vmCalldata = vmCall.vmCalldata;

        emit CallQuarkScript(vmCode, vmCalldata);

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

            function revert_err(err_code) {
                mstore(0, shl(224, err_code))
                revert(0, 4)
            }

            function get_op(vpc, vcodestart, vcodesize) -> op {
                if gt(vpc, vcodesize) {
                    revert_err(0x1dd9f521) // PcOutOfBounds()
                }

                op := shr(248, mload(codeptr(vpc, vcodestart)))
                // log1(0, 0, add(shl(16, vpc), op))
            }

            function vpush(stk, stk_depth, v) -> nextstk, nextstk_depth {
                mstore(stk, v)
                // log2(0x2000, 0x60, stk, v)
                nextstk := add(stk, 0x20)
                nextstk_depth := add(stk_depth, 1)

                if gt(nextstk_depth, 1023) {
                    revert_err(0xa25cba31) // StackOverflow()
                }
            }

            function vpop(stk, stk_depth) -> nextstk, nextstk_depth, v {
                if iszero(stk_depth) {
                    revert_err(0x04671d00) // StackUnderflow()
                }

                v := mload(sub(stk, 0x20))
                nextstk := sub(stk, 0x20)
                nextstk_depth := sub(stk_depth, 1)
            }

            function vset(stk, stk_depth, i, v) {
                if gt(add(stk_depth, i), 1023) {
                    revert_err(0xa25cba31) // StackOverflow()
                }

                let loc := sub(stk, mul(0x20, add(1, i)))
                mstore(loc, v)
            }

            function vpeek(stk, stk_depth, i) -> v {
                if gt(add(i, 1), stk_depth) { // TODO: Double check this math
                    revert_err(0x04671d00) // StackUnderflow()
                }

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
                    mstore8(dst, shr(248, mload(src)))
                    dst := add(dst, 1)
                    src := add(src, 1)
                    size := sub(size, 1)
                }
            }

            function zerofill(dst, size) {
                for {} gt(size, 0) {}
                {
                    // Fill word
                    if gt(size, 31) { // ≥32
                        mstore(dst, 0)
                        dst := add(dst, 32)
                        size := sub(size, 32)
                        continue
                    }

                    // Fill byte
                    //
                    // Note: we can't use `mstore` here to store a full word since we could
                    // truncate past the end of the dst ptr.
                    mstore8(dst, 0)
                    dst := add(dst, 1)
                    size := sub(size, 1)
                }
            }

            // Initialize stack pointer
            let stk_begin := allocate(0x8000)
            let stk := stk_begin
            let stk_depth := 0
            let vmemstart := allocate_unbounded()

            let vcodesize := mload(vmCode)
            let vcodestart := add(vmCode, 0x20)
            let vcalldatasize := mload(vmCalldata)
            let vcalldatastart := add(vmCalldata, 0x20)

            // log3(vcodestart, vcodesize, 0xBEAD0000, vcodesize, vcodestart)
            // log3(vcalldatastart, vcalldatasize, 0xBEAD0001, vcalldatasize, vcalldatastart)

            for { let vpc := 0 } lt(vpc, vcodesize) { vpc := add(vpc, 1) }
            {
                // log3(0, 0, 0xDEED, stk, stk_depth)
                let op := get_op(vpc, vcodestart, vcodesize)
                let stk_size := sub(stk, stk_begin)
                // log3(stk_begin, stk_size, 0xBEAD0002, vpc, op)

                // Special-case PUSH0-PUSH32
                if and(gte(op, 0x5f), lte(op, 0x7f)) {
                    // PUSH0-PUSH32
                    let bytes_to_read := sub(op, 0x5f)
                    let shift_bytes := sub(0x20, bytes_to_read)
                    let vpc_plus_one := add(vpc, 1)

                    if gt(add(bytes_to_read, vpc_plus_one), vcodesize) {
                        revert_err(0xdc779173) // PushOutOfBound()
                    }

                    let push_data_ptr := codeptr(vpc_plus_one, vcodestart)
                    let v := shr(mul(8, shift_bytes), mload(push_data_ptr))
                    vpc := add(vpc, bytes_to_read)
                    stk, stk_depth := vpush(stk, stk_depth, v)
                    continue
                }

                // Special-case DUP1-DUP16
                if and(gte(op, 0x80), lte(op, 0x8f)) {
                    let v := vpeek(stk, stk_depth, sub(op, 0x80))
                    stk, stk_depth := vpush(stk, stk_depth, v)
                    continue
                }

                // Special-case SWAP1-SWAP16
                if and(gte(op, 0x90), lte(op, 0x9f)) {
                    let n := add(sub(op, 0x90), 1)
                    let head := vpeek(stk, stk_depth, 0)
                    let tail := vpeek(stk, stk_depth, n)
                    vset(stk, stk_depth, 0, tail)
                    vset(stk, stk_depth, n, head)
                    continue
                }

                switch op
                case 0x00 { // STOP
                    stop()
                }
                case 0x01 { // ADD
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, add(a, b))
                }
                case 0x02 { // MUL
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, mul(a, b))
                }
                case 0x03 { // SUB
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, sub(a, b))
                }
                case 0x04 { // DIV
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, div(a, b))
                }
                case 0x05 { // SDIV
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, sdiv(a, b))
                }
                case 0x06 { // MOD
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, mod(a, b))
                }
                case 0x07 { // SMOD
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, smod(a, b))
                }
                case 0x08 { // ADDMOD
                    let a, b, n
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth, n := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, addmod(a, b, n))
                }
                case 0x09 { // MULMOD
                    let a, b, n
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth, n := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, mulmod(a, b, n))
                }
                case 0x0a { // EXP
                    let a, expo
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, expo := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, exp(a, expo))
                }
                case 0x0b { // SIGNEXTEND
                    let b, x
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth, x := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, signextend(b, x))
                }
                case 0x10 { // LT
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, lt(a, b))
                }
                case 0x11 { // GT
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, gt(a, b))
                }
                case 0x12 { // SLT
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, slt(a, b))
                }
                case 0x13 { // SGT
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, sgt(a, b))
                }
                case 0x14 { // EQ
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, eq(a, b))
                }
                case 0x15 { // ISZERO
                    let a
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, iszero(a))
                }
                case 0x16 { // AND
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, and(a, b))
                }
                case 0x17 { // OR
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, or(a, b))
                }
                case 0x18 { // XOR
                    let a, b
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth, b := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, xor(a, b))
                }
                case 0x19 { // NOT
                    let a
                    stk, stk_depth, a := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, not(a))
                }
                case 0x1a { // BYTE
                    let i, x
                    stk, stk_depth, i := vpop(stk, stk_depth)
                    stk, stk_depth, x := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, byte(i, x))
                }
                case 0x1b { // SHL
                    let shift, value
                    stk, stk_depth, shift := vpop(stk, stk_depth)
                    stk, stk_depth, value := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, shl(shift, value))
                }
                case 0x1c { // SHR
                    let shift, value
                    stk, stk_depth, shift := vpop(stk, stk_depth)
                    stk, stk_depth, value := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, shr(shift, value))
                }
                case 0x1d { // SAR
                    let shift, value
                    stk, stk_depth, shift := vpop(stk, stk_depth)
                    stk, stk_depth, value := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, sar(shift, value))
                }
                case 0x20 { // SHA3
                    let offset, size
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)
                    let hash := keccak256(memptr(offset, vmemstart), size)
                    stk, stk_depth := vpush(stk, stk_depth, hash)
                }
                case 0x30 { // ADDRESS
                    stk, stk_depth := vpush(stk, stk_depth, address())
                }
                case 0x31 { // BALANCE
                    let addr
                    stk, stk_depth, addr := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, balance(addr))
                }
                case 0x32 { // ORIGIN
                    stk, stk_depth := vpush(stk, stk_depth, origin())
                }
                case 0x33 { // CALLER
                    stk, stk_depth := vpush(stk, stk_depth, caller())
                }
                case 0x34 { // CALLVALUE
                    stk, stk_depth := vpush(stk, stk_depth, callvalue())
                }
                case 0x35 { // CALLDATALOAD *
                    let i, lastbyte
                    stk, stk_depth, i := vpop(stk, stk_depth)
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
                    stk, stk_depth := vpush(stk, stk_depth, v)
                }
                case 0x36 { // CALLDATASIZE *
                    stk, stk_depth := vpush(stk, stk_depth, vcalldatasize)
                }
                case 0x37 { // CALLDATACOPY *
                    let dstoffset, offset, size
                    stk, stk_depth, dstoffset := vpop(stk, stk_depth)
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)

                    let zerofillsz := 0

                    // Fully in deadspace
                    if gt(offset, vcalldatasize) { // TODO: gte?
                        zerofill(memptr(dstoffset, vmemstart), size)
                        continue
                    }

                    if gt(add(offset, size), vcalldatasize) {
                        // Partially filled
                        let size0 := sub(vcalldatasize, offset)
                        zerofillsz := sub(size, size0)
                        size := size0
                    }

                    memcpy(memptr(dstoffset, vmemstart), calldataptr(offset, vcalldatastart), size)

                    if gt(zerofillsz, 0) {
                        zerofill(memptr(add(dstoffset, size), vmemstart), zerofillsz)
                    }
                }
                case 0x38 { // CODESIZE
                    stk, stk_depth := vpush(stk, stk_depth, vcodesize)
                }
                case 0x39 { // CODECOPY
                    let dstoffset, offset, size
                    stk, stk_depth, dstoffset := vpop(stk, stk_depth)
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)

                    if gt(add(offset, size), vcodesize) {
                        // TODO: Improve check
                        revert(0, 0) // out of bounds
                    }
                    memcpy(memptr(dstoffset, vmemstart), calldataptr(offset, vcodesize), size)
                }
                case 0x3a { // GASPRICE
                    stk, stk_depth := vpush(stk, stk_depth, gasprice())
                }
                case 0x3b { // EXTCODESIZE
                    let addr, dstoffset, offset, size
                    stk, stk_depth, addr := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, extcodesize(addr))
                }
                case 0x3c { // EXTCODECOPY
                    let addr, dstoffset, offset, size
                    stk, stk_depth, addr := vpop(stk, stk_depth)
                    stk, stk_depth, dstoffset := vpop(stk, stk_depth)
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)
                    extcodecopy(addr, dstoffset, memptr(offset, vmemstart), size)
                }
                case 0x3d { // RETURNDATASIZE
                    stk, stk_depth := vpush(stk, stk_depth, returndatasize())
                }
                case 0x3e { // RETURNDATACOPY
                    let dstoffset, offset, size
                    stk, stk_depth, dstoffset := vpop(stk, stk_depth)
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)
                    returndatacopy(memptr(dstoffset, vmemstart), offset, size)
                }
                case 0x3f { // EXTCODEHASH
                    let addr
                    stk, stk_depth, addr := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, extcodehash(addr))
                }
                case 0x40 { // BLOCKHASH
                    let blocknumber
                    stk, stk_depth, blocknumber := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, blockhash(blocknumber))
                }
                case 0x41 { // COINBASE
                    stk, stk_depth := vpush(stk, stk_depth, coinbase())
                }
                case 0x42 { // TIMESTAMP
                    stk, stk_depth := vpush(stk, stk_depth, timestamp())
                }
                case 0x43 { // NUMBER
                    stk, stk_depth := vpush(stk, stk_depth, number())
                }
                case 0x44 { // DIFFICULTY
                    // TODO: Disallowed?
                    stk, stk_depth := vpush(stk, stk_depth, difficulty())
                }
                case 0x45 { // GASLIMIT
                    stk, stk_depth := vpush(stk, stk_depth, gaslimit())
                }
                case 0x46 { // CHAINID
                    stk, stk_depth := vpush(stk, stk_depth, chainid())
                }
                case 0x47 { // SELFBALANCE
                    stk, stk_depth := vpush(stk, stk_depth, selfbalance())
                }
                case 0x48 { // BASEFEE
                    stk, stk_depth := vpush(stk, stk_depth, basefee())
                }
                case 0x50 { // POP
                    let unused
                    stk, stk_depth, unused := vpop(stk, stk_depth)
                }
                case 0x51 { // MLOAD
                    let offset
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    let v := mload(memptr(offset, vmemstart))
                    // log2(0, 0, 0xBEEB, v)
                    stk, stk_depth := vpush(stk, stk_depth, v)
                }
                case 0x52 { // MSTORE
                    let offset, v
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, v := vpop(stk, stk_depth)
                    // log2(0, 0, offset, v)
                    mstore(memptr(offset, vmemstart), v)
                }
                case 0x53 { // MSTORE8
                    let offset, v
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, v := vpop(stk, stk_depth)
                    mstore8(memptr(offset, vmemstart), and(v, 0xff))
                }
                case 0x54 { // SLOAD
                    let key
                    stk, stk_depth, key := vpop(stk, stk_depth)
                    stk, stk_depth := vpush(stk, stk_depth, sload(key))
                }
                case 0x55 { // SSTORE
                    let key, value
                    stk, stk_depth, key := vpop(stk, stk_depth)
                    stk, stk_depth, value := vpop(stk, stk_depth)
                    sstore(key, value)
                }
                case 0x56 { // JUMP
                    let dst
                    stk, stk_depth, dst := vpop(stk, stk_depth)
                    if neq(get_op(dst, vcodestart, vcodesize), 0x5b) { // JUMPDEST
                        revert_err(0x5093e196) // InvalidJumpDest()
                    }
                    vpc := dst
                }
                case 0x57 { // JUMPI
                    let dst, cond
                    stk, stk_depth, dst := vpop(stk, stk_depth)
                    stk, stk_depth, cond := vpop(stk, stk_depth)
                    let dstop := get_op(dst, vcodestart, vcodesize)
                    // log3(0, 0, cond, dst, dstop)
                    if neq(dstop, 0x5b) { // JUMPDEST
                        revert_err(0x5093e196) // InvalidJumpDest()
                    }
                    if gt(cond, 0) {
                        vpc := dst
                    }
                }
                case 0x58 { // PC
                    // TODO: Make sure this isn't off by one?
                    stk, stk_depth := vpush(stk, stk_depth, vpc)
                }
                case 0x59 { // MSIZE
                    // let msz := msize()
                    let msz := 0 // TODO: Simulate
                    if gte(msz, 0x4000) {
                        stk, stk_depth := vpush(stk, stk_depth, sub(msz, 0x4000))
                        continue
                    }
                    // else [memory is empty]
                    stk, stk_depth := vpush(stk, stk_depth, 0)
                    continue
                }
                case 0x5a { // GAS
                    stk, stk_depth := vpush(stk, stk_depth, gas())
                }
                case 0x5b { // JUMPDEST
                    // nop
                }
                case 0xa0 { // LOG0
                    let offset, size
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)
                    log0(memptr(offset, vmemstart), size) // TODO: Double check this
                }
                case 0xa1 { // LOG1
                    let offset, size, topic0
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)
                    stk, stk_depth, topic0 := vpop(stk, stk_depth)
                    log1(memptr(offset, vmemstart), size, topic0)
                }
                case 0xa2 { // LOG2
                    let offset, size, topic0, topic1
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)
                    stk, stk_depth, topic0 := vpop(stk, stk_depth)
                    stk, stk_depth, topic1 := vpop(stk, stk_depth)
                    log2(memptr(offset, vmemstart), size, topic0, topic1)
                }
                case 0xa3 { // LOG3
                    let offset, size, topic0, topic1, topic2
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)
                    stk, stk_depth, topic0 := vpop(stk, stk_depth)
                    stk, stk_depth, topic1 := vpop(stk, stk_depth)
                    stk, stk_depth, topic2 := vpop(stk, stk_depth)
                    log3(memptr(offset, vmemstart), size, topic0, topic1, topic2)
                }
                case 0xa4 { // LOG4
                    let offset, size, topic0, topic1, topic2, topic3
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)
                    stk, stk_depth, topic0 := vpop(stk, stk_depth)
                    stk, stk_depth, topic1 := vpop(stk, stk_depth)
                    stk, stk_depth, topic2 := vpop(stk, stk_depth)
                    stk, stk_depth, topic3 := vpop(stk, stk_depth)
                    log4(memptr(offset, vmemstart), size, topic0, topic1, topic2, topic3)
                }
                case 0xf0 { // CREATE
                    let value, offset, size
                    stk, stk_depth, value := vpop(stk, stk_depth)
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)
                    let r := create(value, memptr(offset, vmemstart), size)
                    stk, stk_depth := vpush(stk, stk_depth, r)
                }
                case 0xf1 { // CALL
                    let gasv, addr, value, argsoffset, argssize, retoffset, retsize

                    stk, stk_depth, gasv := vpop(stk, stk_depth)
                    stk, stk_depth, addr := vpop(stk, stk_depth)
                    stk, stk_depth, value := vpop(stk, stk_depth)
                    stk, stk_depth, argsoffset := vpop(stk, stk_depth)
                    stk, stk_depth, argssize := vpop(stk, stk_depth)
                    stk, stk_depth, retoffset := vpop(stk, stk_depth)
                    stk, stk_depth, retsize := vpop(stk, stk_depth)
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
                    stk, stk_depth := vpush(stk, stk_depth, success)
                }
                case 0xf2 { // CALLCODE
                    let gasv, addr, value, argsoffset, argssize, retoffset, retsize

                    stk, stk_depth, gasv := vpop(stk, stk_depth)
                    stk, stk_depth, addr := vpop(stk, stk_depth)
                    stk, stk_depth, value := vpop(stk, stk_depth)
                    stk, stk_depth, argsoffset := vpop(stk, stk_depth)
                    stk, stk_depth, argssize := vpop(stk, stk_depth)
                    stk, stk_depth, retoffset := vpop(stk, stk_depth)
                    stk, stk_depth, retsize := vpop(stk, stk_depth)
                    let success := callcode(
                        gasv,
                        addr,
                        value,
                        memptr(argsoffset, vmemstart),
                        argssize,
                        memptr(retoffset, vmemstart),
                        retsize
                    )
                    stk, stk_depth := vpush(stk, stk_depth, success)
                }
                case 0xf3 { // RETURN
                    let offset, size
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)
                    // let memoffset := sub(memptr(offset, vmemstart), 0x20) // This can truncate other memory, but luckily, we're done now.
                    // mstore(memoffset, size)
                    // log3(memoffset, add(size, 0x20), 0xBEAD0099, offset, size)
                    return(memptr(offset, vmemstart), size) // Change this to be length-prefixed
                }
                case 0xf4 { // DELEGATECALL
                    let gasv, addr, argsoffset, argssize, retoffset, retsize

                    stk, stk_depth, gasv := vpop(stk, stk_depth)
                    stk, stk_depth, addr := vpop(stk, stk_depth)
                    stk, stk_depth, argsoffset := vpop(stk, stk_depth)
                    stk, stk_depth, argssize := vpop(stk, stk_depth)
                    stk, stk_depth, retoffset := vpop(stk, stk_depth)
                    stk, stk_depth, retsize := vpop(stk, stk_depth)
                    let success := delegatecall(
                        gasv,
                        addr,
                        memptr(argsoffset, vmemstart),
                        argssize,
                        memptr(retoffset, vmemstart),
                        retsize
                    )
                    stk, stk_depth := vpush(stk, stk_depth, success)
                }
                case 0xf5 { // CREATE2
                    let value, offset, size, salt
                    stk, stk_depth, value := vpop(stk, stk_depth)
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)
                    stk, stk_depth, salt := vpop(stk, stk_depth)
                    let r := create2(value, memptr(offset, vmemstart), size, salt)
                    stk, stk_depth := vpush(stk, stk_depth, r)
                }
                case 0xfa { // STATICCALL
                    let gasv, addr, argsoffset, argssize, retoffset, retsize

                    stk, stk_depth, gasv := vpop(stk, stk_depth)
                    stk, stk_depth, addr := vpop(stk, stk_depth)
                    stk, stk_depth, argsoffset := vpop(stk, stk_depth)
                    stk, stk_depth, argssize := vpop(stk, stk_depth)
                    stk, stk_depth, retoffset := vpop(stk, stk_depth)
                    stk, stk_depth, retsize := vpop(stk, stk_depth)
                    let success := staticcall(
                        gasv,
                        addr,
                        memptr(argsoffset, vmemstart),
                        argssize,
                        memptr(retoffset, vmemstart),
                        retsize
                    )
                    stk, stk_depth := vpush(stk, stk_depth, success)
                }
                case 0xfd { // REVERT
                    let offset, size
                    stk, stk_depth, offset := vpop(stk, stk_depth)
                    stk, stk_depth, size := vpop(stk, stk_depth)
                    // log3(0, 0, 0xBAAE, offset, size)
                    revert(memptr(offset, vmemstart), size)
                }
                case 0xfe { // INVALID
                    // Technically this should be an invalid, and not a
                    // revert. But sue me.
                    revert(0, 0)
                }
                case 0xff { // SELFDESTRUCT
                    let recipient
                    stk, stk_depth, recipient := vpop(stk, stk_depth)
                    // This is not implemented, but we will simply
                    // take no action. Technically, we should send
                    // all of our Eth away.
                }
                default {
                    // Unknown opcode
                    revert_err(0xd6234725) // NotImplemented()
                }
            }

            // Program ended without returning
            revert_err(0x1dd9f521) // PcOutOfBounds()
        }
    }
}
