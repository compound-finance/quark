pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "../src/CodeJar.sol";
import "../src/Manifest.sol";
import "../src/Relayer.sol";
import "../src/RelayerKafka.sol";

contract DeployUtils is Script {
    using stdJson for string;

    function stringEq(string memory a, string memory b) internal returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function getDeploymentsFile() internal returns (string memory) {
        Chain memory chain = getChain(block.chainid);
        if (stringEq(chain.name, "Anvil")) {
            return "./deployments.local.json";
        } else {
            return "./deployments.json";
        }
    }

    function networkName() internal returns (string memory) {
        Chain memory chain = getChain(block.chainid);
        return chain.name;
    }

    function contractKey(string memory name) internal returns (string memory) {
        return contractKey(name, "");
    }

    function contractKey(string memory name, string memory ext) internal returns (string memory) {
        string memory network = networkName();
        uint256 networkLen;
        uint256 nameLen;
        uint256 extLen;
        assembly {
            networkLen := mload(network)
            nameLen := mload(name)
            extLen := mload(ext)
        }
        string memory res = new string(2 + networkLen + nameLen + extLen);

        assembly {
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
                    mstore8(dst, and(shr(248, mload(src)), 0xff))
                    dst := add(dst, 1)
                    src := add(src, 1)
                    size := sub(size, 1)
                }
            }

            let offset := 32
            mstore8(add(res, offset), 46)
            offset := add(offset, 1)
            memcpy(add(res, offset), add(network, 32), 8)
            offset := add(offset, networkLen)
            mstore8(add(res, offset), 46)
            offset := add(offset, 1)
            memcpy(add(res, offset), add(name, 32), nameLen)
            offset := add(offset, nameLen)
            memcpy(add(res, offset), add(ext, 32), extLen)
        }
        console.log("res: %s", res);
        return res;
    }

    function findExisting(string memory name) external returns (address) {
        string memory json = vm.readFile(getDeploymentsFile());
        bytes memory b = json.parseRaw(contractKey(name));
        address res;
        assembly {
            res := mload(add(b, 0x20))
        }
        if (res == address(0)) {
            return address(0);
        } else {
            return vm.parseJsonAddress(json, contractKey(name));
        }
    }

    function save(string memory name, address addr, bytes memory bytecode) external {
        // string memory json = vm.readFile("./deployments.json");
        // // console.log("json: %s", json);
        // // string memory j = "123456";
        // string memory json_ = vm.serializeAddress(json, "cat", addr);
        // console.log("json: %s", json);
        //vm.writeJson(json_, "./deployments.json");
        string memory deploymentsFile = getDeploymentsFile();
        vm.writeJson(vm.toString(addr), deploymentsFile, contractKey(name));
        vm.writeJson(vm.toString(bytecode), deploymentsFile, contractKey(name, "Bytecode"));
    }
}

contract DeployScript is Script {
    DeployUtils deployUtils;

    function setUp() public {
        deployUtils = new DeployUtils();
    }

    function run() public {
        vm.startBroadcast();
        
        // Get existing CodeJar, if it exists
        CodeJar codeJar = CodeJar(deployUtils.findExisting("CodeJar"));
        if (codeJar == CodeJar(address(0))) {
            console.log("Deploying new CodeJar...");
            codeJar = new CodeJar();
            console.log("CodeJar deployed to %s", address(codeJar));
            deployUtils.save("CodeJar", address(codeJar), type(CodeJar).creationCode);
        } else {
            console.log("CodeJar at %s", address(codeJar));
        }

        // Get existing Manifest, if it exists
        Manifest manifest = Manifest(deployUtils.findExisting("Manifest"));
        if (manifest == Manifest(address(0))) {
            console.log("Deploying new Manifest...");
            manifest = new Manifest(codeJar);
            console.log("Manifest deployed to %s", address(manifest));
            deployUtils.save("Manifest", address(manifest), type(Manifest).creationCode);
        } else {
            console.log("Manifest at %s", address(manifest));
        }

        // Always deploy new Relayer
        Relayer relayer = Relayer(
            payable(manifest.deploy(
                abi.encodePacked(type(RelayerKafka).creationCode, abi.encode(codeJar)),
                "quark-alpha", // TODO: Get from env
                bytes32(uint256(0x1))))); // TODO: Get from env

        deployUtils.save("Relayer", address(relayer), type(RelayerKafka).creationCode);

        console.log("Deployed Relayer to %s", address(relayer));

        vm.stopBroadcast();
    }
}
