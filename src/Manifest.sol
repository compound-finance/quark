// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CodeJar.sol";

contract Manifest {
    error ManifestRunning(address account);
    error ManifestInitFailed(address account, bool create2Failed);
    error ManifestAddressMismatch(address account, address expected, address created);
    error ReadManifestError();
    error EmptyManifestError();

    CodeJar public immutable codeJar;

    mapping(address => address) manifests;

    constructor(CodeJar codeJar_) {
        codeJar = codeJar_;
    }

    function getSalt(address account, string memory name, bytes32 version) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            account,
            keccak256(abi.encode(name)),
            version
        )));
    }

    function getManifestInitCode() public pure returns (bytes memory) {
        return hex"600030610eeb8280a2630ec2a8bb60e41b815260208160048180335af115604f578051803b156040578180918136915af43d82803e15603c573d90f35b3d90fd5b6317b1af2760e11b8252600482fd5b633d0b7ced60e21b8152600490fd";
    }

    /**
     * @notice Helper function to return a manifest address for a given account, name and version.
     */
    function getManifestAddress(address account, string memory name, bytes32 version) external view returns (address) {
        return getManifestAddress(getSalt(account, name, version));
    }

    function getManifestAddress(uint256 salt) internal view returns (address) {
        return address(uint160(uint256(
            keccak256(
                abi.encodePacked(
                    bytes1(0xff),
                    address(this),
                    salt,
                    keccak256(getManifestInitCode())
                )
            )))
        );
    }

    function deploy(bytes calldata initCode, string calldata name, bytes32 version) external returns (address) {
        return deploy_(msg.sender, initCode, name, version);
    }

    function deploy_(address account, bytes calldata initCode, string memory name, bytes32 version) internal returns (address) {
        uint256 salt = getSalt(account, name, version);
        address manifestAddress = getManifestAddress(salt);

        // Ensure a manifest isn't already running
        if (manifests[manifestAddress] != address(0)) {
            revert ManifestRunning(account);
        }

        // Stores the manifest in storage so it can be loaded via `readManifest` in the `create2`
        // constructor code (see `yul/Manifest.yul`).
        manifests[manifestAddress] = codeJar.saveCode(initCode);

        bytes memory manifestInitCode = getManifestInitCode();
        uint256 manifestInitCodeLen = manifestInitCode.length;

        address manifest;

        assembly {
            manifest := create2(0, add(manifestInitCode, 32), manifestInitCodeLen, salt)
        }

        // Ensure that the wallet was created.
        if (uint160(address(manifest)) == 0) {
            revert ManifestInitFailed(account, true);
        }

        if (manifestAddress != manifest) {
            revert ManifestAddressMismatch(account, manifestAddress, manifest);
        }

        // Double ensure it was created by making sure it has code associated with it.
        // TODO: Do we need this double check there's code here?
        uint256 manifestCodeLen;
        assembly {
            manifestCodeLen := extcodesize(manifest)
        }
        if (manifestCodeLen == 0) {
            revert ManifestInitFailed(account, false);
        }

        manifests[manifestAddress] = address(0);

        return manifest;
    }

    function readManifest() external view returns (address) {
        return manifests[msg.sender];
    }
}
