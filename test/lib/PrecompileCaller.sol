// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

contract PrecompileCaller {
    // 0x01
    function ecrecoverCall(bytes32 h, uint8 v, bytes32 r, bytes32 s, address expected) public view {
        (bool success, bytes memory output) = address(0x01).staticcall(abi.encode(h, v, r, s));
        require(success);
        require(abi.decode(output, (address)) == expected);
    }

    // 0x02
    function sha256Call(uint256 numberToHash, bytes memory expected) public view {
        (bool success, bytes memory output) = address(0x02).staticcall(abi.encode(numberToHash));
        require(success);
        require(output.length == expected.length);
        for (uint256 i = 0; i < output.length; i++) {
            require(output[i] == expected[i]);
        }
    }

    // 0x03
    function ripemd160Call(bytes calldata data, bytes20 expected) public view {
        (bool success, bytes memory output) = address(0x03).staticcall(data);
        require(success);
        bytes20 result = bytes20(abi.decode(output, (bytes32)) << 96);
        require(result == expected);
    }

    // 0x04
    function dataCopyCall(bytes memory data) public {
        bytes memory out = new bytes(data.length);
        assembly {
            let len := mload(data)
            if iszero(call(gas(), 0x04, 0, add(data, 0x20), len, add(out, 0x20), len)) { invalid() }
        }

        for (uint256 i = 0; i < data.length; i++) {
            require(data[i] == out[i]);
        }
    }

    // 0x05
    function bigModExpCall(bytes32 base, bytes32 exponent, bytes32 modulus, bytes32 expected) public {
        bytes32 result;
        assembly {
            let memPtr := mload(0x40)
            mstore(memPtr, 0x20)
            mstore(add(memPtr, 0x20), 0x20)
            mstore(add(memPtr, 0x40), 0x20)

            mstore(add(memPtr, 0x60), base)
            mstore(add(memPtr, 0x80), exponent)
            mstore(add(memPtr, 0xa0), modulus)

            let success := call(gas(), 0x05, 0, memPtr, 0xc0, memPtr, 0x20)
            if iszero(success) { revert(0, 0) }
            result := mload(memPtr)
        }

        require(result == expected);
    }

    // 0x06
    function bn256AddCall(uint256 ax, uint256 ay, uint256 bx, uint256 by, uint256[2] memory expected) public {
        uint256[4] memory input;
        input[0] = ax;
        input[1] = ay;
        input[2] = bx;
        input[3] = by;
        uint256[2] memory output;
        assembly {
            let success := call(gas(), 0x06, 0, input, 0x80, output, 0x40)
            if iszero(success) { revert(0, 0) }
        }

        require(output[0] == expected[0]);
        require(output[1] == expected[1]);
    }

    // 0x07
    function bn256ScalarMulCall(uint256 x, uint256 y, uint256 scalar, uint256[2] memory expected) public {
        uint256[3] memory input;
        input[0] = x;
        input[1] = y;
        input[2] = scalar;
        uint256[2] memory output;
        assembly {
            let success := call(gas(), 0x07, 0, input, 0x60, output, 0x40)
            if iszero(success) { revert(0, 0) }
        }

        require(output[0] == expected[0]);
        require(output[1] == expected[1]);
    }

    // 0x08
    function bn256PairingCall(bytes memory input, bytes32 expected) public {
        uint256 len = input.length;
        bytes32 output;
        require(len % 192 == 0);
        assembly {
            let memPtr := mload(0x40)
            let success := call(gas(), 0x08, 0, add(input, 0x20), len, memPtr, 0x20)
            if iszero(success) { revert(0, 0) }
            output := mload(memPtr)
        }

        require(output == expected);
    }

    // 0x09
    function blake2FCall(
        uint32 rounds,
        bytes32[2] memory h,
        bytes32[4] memory m,
        bytes8[2] memory t,
        bool f,
        bytes32[2] memory expected
    ) public view {
        bytes32[2] memory output;
        bytes memory args = abi.encodePacked(rounds, h[0], h[1], m[0], m[1], m[2], m[3], t[0], t[1], f);
        assembly {
            let success := staticcall(gas(), 0x09, add(args, 32), 0xd5, output, 0x40)
            if iszero(success) { revert(0, 0) }
        }

        require(output[0] == expected[0]);
        require(output[1] == expected[1]);
    }
}
