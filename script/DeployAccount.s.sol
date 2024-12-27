// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import "src/MSAFactory.sol";
import { Bootstrap, BootstrapConfig } from "src/utils/Bootstrap.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { IEntryPoint } from "account-abstraction/interfaces/IEntryPoint.sol";
import {
    ModeLib,
    ModeCode,
    CallType,
    ExecType,
    ModeSelector,
    ModePayload,
    CALLTYPE_DELEGATECALL,
    EXECTYPE_DEFAULT,
    MODE_DEFAULT
} from "src/lib/ModeLib.sol";
import "src/interfaces/IERC7579Account.sol";
import { ExecutionLib } from "src/lib/ExecutionLib.sol";

import "forge-std/console2.sol";

/**
 * @title DeployAccount
 * @author @kopy-kat
 */
contract DeployAccountScript is Script {
    // NOTE: this code creates a new MSA and initializes it with the given modules
    // then it calls the execute function of the MSA
    function run() public {
        // factory of MSAs deployed in virtual net (we need this scripted)
        MSAFactory factory = MSAFactory(address(0x059d33C2C93426824c380c59E6E85Da7781f70D7));
        // bootstrap contract to generate calldata (we should have this scripted)
        Bootstrap bootstrap =
            Bootstrap(payable(address(0xc672F201E96790a58BA782F9077Aa32e5a6cB9ac)));
        // validator contract - we need our own validation logic? Or not
        // NOTE: there is a contract called SimpleExecutionValidator - shouldn't we use this
        address initialValidator = address(0x45b898aA19A8C4d127e2381a2A0cDC6B286Db253);

        bytes32 salt = bytes32(uint256(1));

        // Create config for initial modules
        BootstrapConfig[] memory validators = new BootstrapConfig[](1);
        validators[0] = BootstrapConfig({ module: initialValidator, data: "" });
        BootstrapConfig[] memory executors = new BootstrapConfig[](0);
        // TODO Shouldn't we have superExecutor as an executor here?
        BootstrapConfig memory hook;
        BootstrapConfig[] memory fallbacks = new BootstrapConfig[](1);

        // This init code is used to install all initial modules above in the MSA
        bytes memory _initCode =
            bootstrap._getInitMSACalldata(validators, executors, hook, fallbacks);

        // Get address of new account
        address account = factory.getAddress(salt, _initCode);
        console2.log("--------------- account", account);

        // Pack the initcode to include in the userOp
        // this is the init code to deploy the smart account
        bytes memory initCode = abi.encodePacked(
            address(factory),
            abi.encodeWithSelector(factory.createAccount.selector, salt, _initCode)
        );

        // TODO: auto-add entrypoint to the VNET as verified? how?
        IEntryPoint entryPoint = IEntryPoint(address(0x0000000071727De22E5E9d8BAf0edAc6f37da032));

        // Create the userOp and add the data
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = address(account);

        uint192 key = uint192(bytes24(bytes20(address(initialValidator))));
        userOp.nonce = entryPoint.getNonce(address(account), key);

        userOp.initCode = initCode;
        // NOTE: why not use executeFromExecutor here if are doing this via SuperExecutor?
        userOp.callData = abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(0), uint256(1), ""))
        );

        // ModeLib.encodeSimpleSingle() -> bytes32 with the following
        /*
        callType (1 byte): 0x00 for a single call, 0x01 for a batch call, 0xfe for staticcall and
            0xff for delegatecall
        execType (1 byte): 0x00 for executions that revert on failure, 0x01 for executions that do
            not revert on failure but implement some form of error handling
            unused (4 bytes): this range is reserved for future standardization
        modeSelector (4 bytes): an additional mode selector that can be used to create further
            execution modes
            modePayload (22 bytes): additional data to be passed
        */
        // ExecutionLib.encodeSingle(address(0), uint256(1), "") -> bytes calldata
        /*
            userOpCalldata = abi.encodePacked(target, value, callData);
            target: address(0)
            value: uint256(1)
            callData: ""
        */

        // Create userOps array
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        console2.log(account);

        vm.startBroadcast();

        entryPoint.handleOps{ gas: 8_000_000 }(userOps, payable(account));

        vm.stopBroadcast();
    }

    function getDefaultUserOp() internal pure returns (PackedUserOperation memory userOp) {
        userOp = PackedUserOperation({
            sender: address(0),
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(abi.encodePacked(uint128(3e6), uint128(1e6))),
            preVerificationGas: 3e5,
            gasFees: bytes32(abi.encodePacked(uint128(3e5), uint128(1e7))),
            paymasterAndData: bytes(""),
            signature: abi.encodePacked(hex"41414141")
        });
    }
}
