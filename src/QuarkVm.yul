object "QuarkVm" {
    /** A simple Evm ... vm.
      *
      */

    code {
        // Store the creator in slot zero.
        sstore(0, caller())

        // Deploy the contract
        datacopy(0, dataoffset("QuarkVm_"), datasize("QuarkVm_"))
        return(0, datasize("QuarkVm_"))
    }

    object "QuarkVm_" {
        code {
            /**
              *
              * Memory:
              *   0x00 : Scratch
              *   0x20 : Scratch
              *   0x40 : Scratch
              *   0x60 : Scratch
              *   0x80 : Reserved
              *   0xa0 : Reserved
              *   0xc0 : Reserved
              *   0xe0 : Reserved
              *  0x100-: calldata
              // TODO: I need to cap the total program size or pass around an offset
              * 0x2000 : stk[0]
              * 0x4000 : mem0 // TODO: This is wrong and sucks
              * 
              */

            function get_op(vpc) -> op {
                op := shr(248, mload(add(0x100, vpc)))
                log1(0, 0, add(shl(16, vpc), op))
            }

            function vpush(stk, v) -> next_stk {
                // TODO: Check the stack is full
                mstore(stk, v)
                // log2(0x2000, 0x60, stk, v)
                next_stk := add(stk, 0x20)
            }

            function vpop(stk) -> next_stk, v {
                // TODO: Check the stack is empty
                v := mload(sub(stk, 0x20))
                next_stk := sub(stk, 0x20)
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

            function map_offset(offset) -> offset_ {
                offset_ := add(offset, 0x4000)
            }

            // Initialize stack pointer
            let stk := 0x2000

            let prog_sz := calldatasize()

            // Copy in calldata to 0x100
            calldatacopy(0x100, 0, calldatasize())

            for { let vpc := 0 } lt(vpc, prog_sz) { vpc := add(vpc, 1) }
            {
                // TODO: I wonder if there's better ways to loopsies
                let op := get_op(vpc)

                // Special-case PUSH0-PUSH32
                if and(gte(op, 0x5f), lte(op, 0x7f)) {
                    // TODO: We should check for end of memory here as invalid

                    // PUSH0-PUSH32
                    let v := shr(mul(8, sub(0x7f, op)), mload(add(0x101, vpc)))
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
                    let hash := keccak256(map_offset(offset), size)
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
                    // TODO: Consider calldata here
                    let i
                    stk, i := vpop(stk)
                    stk := vpush(stk, calldataload(i))
                }
                case 0x36 { // CALLDATASIZE
                    stk := vpush(stk, calldatasize())
                }
                case 0x37 { // CALLDATACOPY
                    let dst_offset, offset, size
                    stk, dst_offset := vpop(stk)
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    calldatacopy(dst_offset, map_offset(offset), size)
                }
                case 0x38 { // CODESIZE
                    stk := vpush(stk, codesize())
                }
                case 0x39 { // CODECOPY
                    let dst_offset, offset, size
                    stk, dst_offset := vpop(stk)
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    codecopy(dst_offset, map_offset(offset), size)
                }
                case 0x3a { // GASPRICE
                    stk := vpush(stk, gasprice())
                }
                case 0x3b { // EXTCODESIZE
                    let addr, dst_offset, offset, size
                    stk, addr := vpop(stk)
                    stk := vpush(stk, extcodesize(addr))
                }
                case 0x3c { // EXTCODECOPY
                    let addr, dst_offset, offset, size
                    stk, addr := vpop(stk)
                    stk, dst_offset := vpop(stk)
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    extcodecopy(addr, dst_offset, map_offset(offset), size)
                }
                case 0x3d { // RETURNDATASIZE
                    stk := vpush(stk, returndatasize())
                }
                case 0x3e { // RETURNDATACOPY
                    let dst_offset, offset, size
                    stk, dst_offset := vpop(stk)
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    returndatacopy(dst_offset, map_offset(offset), size)
                }
                case 0x3f { // EXTCODEHASH
                    let addr
                    stk, addr := vpop(stk)
                    stk := vpush(stk, extcodehash(addr))
                }
                case 0x40 { // BLOCKHASH
                    let block_number
                    stk, block_number := vpop(stk)
                    stk := vpush(stk, blockhash(block_number))
                }
                case 0x41 { // COINBASE
                    stk := vpush(stk, coinbase())
                }
                case 0x42 { // TIMESTMAP
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
                    let _
                    stk, _ := vpop(stk)
                }
                case 0x51 { // MLOAD
                    let offset
                    stk, offset := vpop(stk)
                    let v := mload(map_offset(offset))
                    stk := vpush(stk, v)
                }
                case 0x52 { // MSTORE
                    let offset, v
                    stk, offset := vpop(stk)
                    stk, v := vpop(stk)
                    mstore(map_offset(offset), v)
                }
                case 0x53 { // MSTORE8
                    let offset, v
                    stk, offset := vpop(stk)
                    stk, v := vpop(stk)
                    mstore8(map_offset(offset), and(v, 0xff))
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
                    if neq(get_op(dst), 0x5B) { // JUMPDEST
                        // Provide a better way to sim a jump failure
                        revert(0, 0)
                    }
                    vpc := add(dst, 1)
                }
                case 0x57 { // JUMPI
                    let dst, cond
                    stk, dst := vpop(stk)
                    stk, cond := vpop(stk)
                    log2(0, 0, cond, dst)
                    if neq(get_op(dst), 0x5B) { // JUMPDEST
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
                    let msz := msize()
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
                    log0(map_offset(offset), size) // TODO: Double check this
                }
                case 0xa1 { // LOG1
                    let offset, size, topic0
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    stk, topic0 := vpop(stk)
                    log1(map_offset(offset), size, topic0)
                }
                case 0xa2 { // LOG2
                    let offset, size, topic0, topic1
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    stk, topic0 := vpop(stk)
                    stk, topic1 := vpop(stk)
                    log2(map_offset(offset), size, topic0, topic1)
                }
                case 0xa3 { // LOG3
                    let offset, size, topic0, topic1, topic2
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    stk, topic0 := vpop(stk)
                    stk, topic1 := vpop(stk)
                    stk, topic2 := vpop(stk)
                    log3(map_offset(offset), size, topic0, topic1, topic2)
                }
                case 0xa4 { // LOG4
                    let offset, size, topic0, topic1, topic2, topic3
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    stk, topic0 := vpop(stk)
                    stk, topic1 := vpop(stk)
                    stk, topic2 := vpop(stk)
                    stk, topic3 := vpop(stk)
                    log4(map_offset(offset), size, topic0, topic1, topic2, topic3)
                }
                case 0xf0 { // CREATE
                    let value, offset, size
                    stk, value := vpop(stk)
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    let r := create(value, map_offset(offset), size)
                    stk := vpush(stk, r)
                }
                case 0xf1 { // CALL
                    let gas_, addr, value, args_offset, args_size, ret_offset, ret_size

                    stk, gas_ := vpop(stk)
                    stk, addr := vpop(stk)
                    stk, value := vpop(stk)
                    stk, args_offset := vpop(stk)
                    stk, args_size := vpop(stk)
                    stk, ret_offset := vpop(stk)
                    stk, ret_size := vpop(stk)
                    log3(0, 0, gas_, addr, value)
                    log2(
                        map_offset(args_offset),
                        args_size,
                        args_offset,
                        args_size
                    )
                    log2(0, 0, ret_offset, ret_size)
                    let success := call(
                        gas_,
                        addr,
                        value,
                        map_offset(args_offset),
                        args_size,
                        map_offset(ret_offset),
                        ret_size
                    )
                    stk := vpush(stk, success)
                }
                case 0xf2 { // CALLCODE
                    let gas_, addr, value, args_offset, args_size, ret_offset, ret_size

                    stk, gas_ := vpop(stk)
                    stk, addr := vpop(stk)
                    stk, value := vpop(stk)
                    stk, args_offset := vpop(stk)
                    stk, args_size := vpop(stk)
                    stk, ret_offset := vpop(stk)
                    stk, ret_size := vpop(stk)
                    let success := callcode(
                        gas_,
                        addr,
                        value,
                        map_offset(args_offset),
                        args_size,
                        map_offset(ret_offset),
                        ret_size
                    )
                    stk := vpush(stk, success)
                }
                case 0xf3 { // RETURN
                    let offset, size
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    return(map_offset(offset), size)
                }
                case 0xf4 { // DELEGATECALL
                    let gas_, addr, args_offset, args_size, ret_offset, ret_size

                    stk, gas_ := vpop(stk)
                    stk, addr := vpop(stk)
                    stk, args_offset := vpop(stk)
                    stk, args_size := vpop(stk)
                    stk, ret_offset := vpop(stk)
                    stk, ret_size := vpop(stk)
                    let success := delegatecall(
                        gas_,
                        addr,
                        map_offset(args_offset),
                        args_size,
                        map_offset(ret_offset),
                        ret_size
                    )
                    stk := vpush(stk, success)
                }
                case 0xf5 { // CREATE2
                    let value, offset, size, salt
                    stk, value := vpop(stk)
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    stk, salt := vpop(stk)
                    let r := create2(value, map_offset(offset), size, salt)
                    stk := vpush(stk, r)
                }
                case 0xfa { // STATICCALL
                    let gas_, addr, args_offset, args_size, ret_offset, ret_size

                    stk, gas_ := vpop(stk)
                    stk, addr := vpop(stk)
                    stk, args_offset := vpop(stk)
                    stk, args_size := vpop(stk)
                    stk, ret_offset := vpop(stk)
                    stk, ret_size := vpop(stk)
                    let success := staticcall(
                        gas_,
                        addr,
                        map_offset(args_offset),
                        args_size,
                        map_offset(ret_offset),
                        ret_size
                    )
                    stk := vpush(stk, success)
                }
                case 0xfd { // REVERT
                    let offset, size
                    stk, offset := vpop(stk)
                    stk, size := vpop(stk)
                    revert(map_offset(offset), size)
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
                    // TODO: better
                    revert(0, 0)
                }
            }

            // TODO: Find a better way to stop
            return (0x2000, 0x60) // Just return some of the stack
        }
    }
}
