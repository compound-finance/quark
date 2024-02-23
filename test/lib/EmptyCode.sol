pragma solidity "0.8.23";

contract EmptyCode {
    // NOTE: force the solidity compiler to produce empty code when this is deployed
    constructor() {
        assembly {
            return(0x0, 0)
        }
    }
}
