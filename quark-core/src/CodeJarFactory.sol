// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {CodeJar} from "./CodeJar.sol";

contract CodeJarFactory {
    CodeJar public immutable codeJar;

    constructor() {
        codeJar = new CodeJar{salt: 0}();
    }
}
