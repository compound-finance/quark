// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./lib/YulHelper.sol";
import "./lib/Counter.sol";
import "./lib/PayScript.sol";
import "../examples/PayLog.sol";
import "./lib/SigUtils.sol";

import "../src/Relayer.sol";
import "../src/RelayerMetamorphic.sol";

interface SearcherScript {
    function submitSearch(Relayer relayer, bytes calldata relayerCalldata, address recipient, address payToken, uint256 expectedWindfall) external;
}

interface GasSearcherScript {
    function submitSearch(Relayer relayer, bytes calldata relayerCalldata, address recipient, address payToken, address payTokenOracle, uint256 expectedWindfall, uint256 gasPrice) external;
}

contract OracleMock {
    uint256 private answer;

    constructor(uint256 answer_) {
        answer = answer_;
    }

    function latestAnswer() external view returns (uint256) {
        return answer;
    }
}

contract QuarkTest is Test {
    event Ping(uint256 value);
    event Hello(uint256 n);

    Relayer public relayer;
    Counter public counter;
    ERC20Mock public token;
    OracleMock public oracle;
    SigUtils public sigUtils;

    uint256 internal accountPrivateKey;
    uint256 internal searcherPrivateKey;

    address internal account;
    address internal searcher;

    constructor() {
        relayer = new RelayerMetamorphic();
        console.log("Relayer deployed to: %s", address(relayer));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        token = new ERC20Mock();
        console.log("Token deployed to: %s", address(token));

        oracle = new OracleMock(18446744073709910265);
        console.log("Oracle deployed to: %s", address(oracle));

        sigUtils = new SigUtils(relayer.DOMAIN_SEPARATOR());

        accountPrivateKey = 0xA11CE;
        searcherPrivateKey = 0xB0B;

        account = vm.addr(accountPrivateKey);
        searcher = vm.addr(searcherPrivateKey);

        console.log("Account: %s", address(account));
        console.log("Searcher: %s", address(searcher));

        token.mint(relayer.getQuarkAddress(account), 100e18);
    }

    function setUp() public {
        // nothing
    }

    function testSubmitTrxScript() public {
        bytes memory incrementer = new YulHelper().get("Incrementer.yul/Incrementer.json");
        assertEq(counter.number(), 0);

        TrxScript memory trxScript = TrxScript({
            account: account,
            nonce: 0,
            reqs: new uint32[](0),
            trxScript: incrementer,
            trxCalldata: hex"",
            expiry: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(trxScript);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(accountPrivateKey, digest);

        vm.prank(searcher, searcher);
        bytes memory data = relayer.runTrxScript(
            trxScript.account,
            trxScript.nonce,
            trxScript.reqs,
            trxScript.trxScript,
            trxScript.trxCalldata,
            trxScript.expiry,
            v,
            r,
            s
        );

        assertEq(data, abi.encode());
        assertEq(counter.number(), 3);
    }

    function testCannotDoubleSubmit() public {
        bytes memory incrementer = new YulHelper().get("Incrementer.yul/Incrementer.json");
        assertEq(counter.number(), 0);

        TrxScript memory trxScript = TrxScript({
            account: account,
            nonce: 0,
            reqs: new uint32[](0),
            trxScript: incrementer,
            trxCalldata: hex"",
            expiry: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(trxScript);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(accountPrivateKey, digest);

        vm.prank(searcher, searcher);
        bytes memory data0 = relayer.runTrxScript(
            trxScript.account,
            trxScript.nonce,
            trxScript.reqs,
            trxScript.trxScript,
            trxScript.trxCalldata,
            trxScript.expiry,
            v,
            r,
            s
        );

        assertEq(data0, abi.encode());
        assertEq(counter.number(), 3);

        vm.prank(searcher, searcher);
        vm.expectRevert(bytes(hex"6aa319b1"));
        bytes memory data1 = relayer.runTrxScript(
            trxScript.account,
            trxScript.nonce,
            trxScript.reqs,
            trxScript.trxScript,
            trxScript.trxCalldata,
            trxScript.expiry,
            v,
            r,
            s
        );

        assertEq(data1, abi.encode());
        assertEq(counter.number(), 3);
    }

    function testGivenReqs() public {
        bytes memory incrementer = new YulHelper().get("Incrementer.yul/Incrementer.json");
        assertEq(counter.number(), 0);

        TrxScript memory trxScript0 = TrxScript({
            account: account,
            nonce: 5,
            reqs: new uint32[](0),
            trxScript: incrementer,
            trxCalldata: hex"",
            expiry: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(trxScript0);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(accountPrivateKey, digest);

        vm.prank(searcher, searcher);
        bytes memory data0 = relayer.runTrxScript(
            trxScript0.account,
            trxScript0.nonce,
            trxScript0.reqs,
            trxScript0.trxScript,
            trxScript0.trxCalldata,
            trxScript0.expiry,
            v,
            r,
            s
        );

        assertEq(data0, abi.encode());
        assertEq(counter.number(), 3);

        uint32[] memory reqs = new uint32[](1);
        reqs[0] = 5;

        TrxScript memory trxScript1 = TrxScript({
            account: account,
            nonce: 10,
            reqs: reqs,
            trxScript: incrementer,
            trxCalldata: hex"",
            expiry: 1 days
        });

        // TODO: We're disagreeing on how to encode reqs!
        vm.prank(searcher, searcher);
        bytes memory data1 = relayer.runTrxScript(
            trxScript1.account,
            trxScript1.nonce,
            trxScript1.reqs,
            trxScript1.trxScript,
            trxScript1.trxCalldata,
            trxScript1.expiry,
            v,
            r,
            s
        );

        assertEq(data1, abi.encode());
        assertEq(counter.number(), 3);
    }

    function testSearcher() public {
        bytes memory incrementer = new YulHelper().get("PaySearcher.yul/PaySearcher.json");
        assertEq(counter.number(), 0);
        assertEq(token.balanceOf(relayer.getQuarkAddress(account)), 100e18);
        assertEq(token.balanceOf(searcher), 0);

        TrxScript memory trxScript = TrxScript({
            account: account,
            nonce: 0,
            reqs: new uint32[](0),
            trxScript: incrementer,
            trxCalldata: hex"",
            expiry: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(trxScript);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(accountPrivateKey, digest);

        vm.prank(searcher, searcher);
        bytes memory data = relayer.runTrxScript(
            trxScript.account,
            trxScript.nonce,
            trxScript.reqs,
            trxScript.trxScript,
            trxScript.trxCalldata,
            trxScript.expiry,
            v,
            r,
            s
        );

        assertEq(token.balanceOf(relayer.getQuarkAddress(account)), 50e18);
        assertEq(token.balanceOf(searcher), 50e18);

        assertEq(data, abi.encode());
        assertEq(counter.number(), 11);
    }

    function testSearcherSubmitTrxScript() public {
        bytes memory searcherScript = new YulHelper().get("Searcher.yul/Searcher.json");
        bytes memory incrementer = new YulHelper().get("PaySearcher.yul/PaySearcher.json");
        assertEq(counter.number(), 0);

        TrxScript memory trxScript = TrxScript({
            account: account,
            nonce: 0,
            reqs: new uint32[](0),
            trxScript: incrementer,
            trxCalldata: hex"",
            expiry: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(trxScript);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(accountPrivateKey, digest);

        vm.prank(searcher, searcher);
        bytes memory relayerCalldata = abi.encodeCall(relayer.runTrxScript, (
            trxScript.account,
            trxScript.nonce,
            trxScript.reqs,
            trxScript.trxScript,
            trxScript.trxCalldata,
            trxScript.expiry,
            v,
            r,
            s
        ));

        bytes memory submitSearch = abi.encodeCall(SearcherScript.submitSearch, (relayer, relayerCalldata, searcher, address(token), 50e18));
        bytes memory data = relayer.runQuark(searcherScript, submitSearch);

        assertEq(data, abi.encode());
        assertEq(counter.number(), 11);
    }

    // TODO: Test no windfall or insufficient windfall or reverting

    function testGasSearcherSubmitTrxScript() public {
        bytes memory searcherScript = new YulHelper().get("GasSearcher.yul/Searcher.json");
        bytes memory incrementer = new YulHelper().get("PaySearcher.yul/PaySearcher.json");
        assertEq(counter.number(), 0);

        TrxScript memory trxScript = TrxScript({
            account: account,
            nonce: 0,
            reqs: new uint32[](0),
            trxScript: incrementer,
            trxCalldata: hex"",
            expiry: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(trxScript);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(accountPrivateKey, digest);

        bytes memory relayerCalldata = abi.encodeCall(relayer.runTrxScript, (
            trxScript.account,
            trxScript.nonce,
            trxScript.reqs,
            trxScript.trxScript,
            trxScript.trxCalldata,
            trxScript.expiry,
            v,
            r,
            s
        ));

        // Checks that we make at least 1e6 USDC
        bytes memory submitSearch = abi.encodeCall(GasSearcherScript.submitSearch, (relayer, relayerCalldata, searcher, address(token), address(oracle), 1e6, 1 gwei));
        
        vm.prank(searcher, searcher);
        bytes memory data = relayer.runQuark(searcherScript, submitSearch);

        assertEq(data, abi.encode());
        assertEq(counter.number(), 11);
    }

    function testGasSearcherSubmitPayLog() public {
        bytes memory searcherScript = new YulHelper().get("GasSearcher.yul/Searcher.json");
        bytes memory payLogCode = new YulHelper().getDeployed("PayLogScript.yul/PayLog_54.json");
        assertEq(counter.number(), 0);

        TrxScript memory trxScript = TrxScript({
            account: account,
            nonce: 0,
            reqs: new uint32[](0),
            trxScript: payLogCode,
            trxCalldata: abi.encodeCall(PayLog.payLog, (IErc20(address(token)), 5e6, 55)),
            expiry: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(trxScript);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(accountPrivateKey, digest);

        bytes memory relayerCalldata = abi.encodeCall(relayer.runTrxScript, (
            trxScript.account,
            trxScript.nonce,
            trxScript.reqs,
            trxScript.trxScript,
            trxScript.trxCalldata,
            trxScript.expiry,
            v,
            r,
            s
        ));

        // Checks that we make at least 1e6 USDC
        bytes memory submitSearch = abi.encodeCall(GasSearcherScript.submitSearch, (relayer, relayerCalldata, searcher, address(token), address(oracle), 1e6, 1 gwei));
        
        // TODO: Check who emitted.
        vm.expectEmit(false, false, false, true);
        emit Hello(55);

        vm.prank(searcher, searcher);
        bytes memory data = relayer.runQuark(searcherScript, submitSearch);

        assertEq(data, abi.encode());
    }
}
