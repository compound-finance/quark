// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./lib/YulHelper.sol";
import "./lib/Counter.sol";
import "./lib/SigUtils.sol";

import "../src/Relayer.sol";

contract QuarkTest is Test {
    event Ping(uint256 value);

    Relayer public relayer;
    Counter public counter;
    SigUtils public sigUtils;

    uint256 internal accountPrivateKey;
    uint256 internal searcherPrivateKey;

    address internal account;
    address internal searcher;

    constructor() {
        relayer = new Relayer();
        console.log("Relayer deployed to: %s", address(relayer));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        sigUtils = new SigUtils(relayer.DOMAIN_SEPARATOR());

        accountPrivateKey = 0xA11CE;
        searcherPrivateKey = 0xB0B;

        account = vm.addr(accountPrivateKey);
        searcher = vm.addr(searcherPrivateKey);

        console.log("Account: %s", address(account));
        console.log("Searcher: %s", address(searcher));
    }

    function setUp() public {
        // nothing
    }

    function testSubmitTrxScript() public {
        bytes memory incrementer = new YulHelper().get("Incrementer.yul/Incrementer.json");
        assertEq(counter.number(), 0);

        SigUtils.TrxScript memory trxScript = SigUtils.TrxScript({
            account: account,
            nonce: 0,
            reqs: new uint32[](0),
            trxScript: incrementer,
            expiry: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(trxScript);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(accountPrivateKey, digest);

        // TODO: Run as searcher
        bytes memory data = relayer.runTrxScript(
            trxScript.account,
            trxScript.nonce,
            trxScript.reqs,
            trxScript.trxScript,
            trxScript.expiry,
            v,
            r,
            s
        );

        assertEq(data, abi.encode());
        assertEq(counter.number(), 3);
    }
}
