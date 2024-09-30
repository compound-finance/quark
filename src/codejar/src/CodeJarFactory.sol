// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {CodeJar} from "codejar/src/CodeJar.sol";

/**
 * @title Code Jar Factory
 * @notice A factory for deploying Code Jar to a content-deterministic address
 * @author Compound Labs, Inc.
 */
contract CodeJarFactory {
    CodeJar public immutable codeJar;

    constructor() {
        codeJar = new CodeJar{salt: 0}();
    }
}
