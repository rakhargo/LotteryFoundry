// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { DeployRaffle } from "script/DeployRaffle.s.sol";
import { Raffle } from "src/Raffle.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { Vm } from "forge-std/Vm.sol";
import { VRFCoordinatorV2_5Mock } from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint entranceFee;
    uint interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint subscriptionId;

    address public PLAYER = makeAddr("player");
    uint public constant STARTING_PLAYER_BALANCE = 10 ether;

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializedOpen() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testEnterRaffleNotEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughETH.selector);
        raffle.enterRaffle();
    }

    function testEnterRaffleRecordPlayer() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{ value: entranceFee }();

        address player = raffle.getPlayer(0);
        assert(player == PLAYER);
    }

    function testEnterRaffleEmitEvent() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        raffle.enterRaffle{ value: entranceFee }();
    }

    function testEnterRaffleWhileCalculating() public raffleEntered {
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__NotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{ value: entranceFee }();
    }
    
    function testCheckUpkeepRaffleNotOpen() public raffleEntered {
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepTimeNotPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{ value: entranceFee }();

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepParametersGood() public raffleEntered {
        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    function testPerformUpkeepWithCheckUpkeepTrue() public raffleEntered {

        raffle.performUpkeep("");
    }

    function testPerformUpkeepWithCheckUpkeepFalse() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{ value: entranceFee }();
        uint currentBalance = entranceFee;
        uint numPlayers = 1;
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        vm.expectRevert(abi.encodeWithSelector(
            Raffle.Raffle__UpkeepNotNeeded.selector,
            currentBalance,
            numPlayers,
            uint(raffleState)
        ));
        raffle.performUpkeep("");
    }

    modifier raffleEntered {
        vm.prank(PLAYER);
        raffle.enterRaffle{ value: entranceFee }();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepEmitEvent() public raffleEntered {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint(requestId) > 0);
        assert(uint(raffleState) == uint(Raffle.RaffleState.CALCULATING));
    }

    function testFulFillRandomWordsAfterPerformUpkeep(uint randomRequestId) public raffleEntered {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }
}