// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { VRFConsumerBaseV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Raffle Contract
 * @author Rakha Dhifiargo
 * @notice This contract is for creating a raffle system.
 * @dev Implements Chainlink VRFv2.5
 */

contract Raffle is VRFConsumerBaseV2Plus {
    // errors
    error Raffle__NotEnoughETH();
    error Raffle__TransferFailed();
    error Raffle__NotOpen();
    error Raffle__UpkeepNotNeeded(uint balance, uint playersLength, uint raffleState);
    
    // type declarations
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    // state variables
    uint16 private constant REQUEST_CONFIRMATIONS = 3; // default is 3
    uint32 private constant NUM_WORDS = 1; // 
    uint private immutable i_entranceFee;
    uint private immutable i_interval; // duration of the lottery in seconds
    bytes32 private immutable i_keyHash;
    uint private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState; // start as OPEN

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    constructor(uint entranceFee, uint interval, address vrfCoordinator, bytes32 gasLane, uint subscriptionId, uint32 callbackGasLimit) 
    VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) { // check if the player has sent enough ETH
            revert Raffle__NotEnoughETH();
        }
        if (s_raffleState != RaffleState.OPEN) { // check if the raffle is open
            revert Raffle__NotOpen(); 
        }

        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev This function is called by the Chainlink Node to check if upkeep is needed.
     * @param - ignored
     * @return upkeepNeeded - true 
     * @return - ignored
     */
    function checkUpkeep(bytes memory /* checkData */) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool timePassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;

        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
        
        return (upkeepNeeded, "");
    }

    // pick winner
    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                VRFV2PlusClient.ExtraArgsV1({
                    // nativePayment: enableNativePayment
                    nativePayment: false // false for using LINK token, otherwise true
                })
            )
        });

        s_vrfCoordinator.requestRandomWords(request);

    }

    function fulfillRandomWords(uint256, /* requestId */ uint256[] calldata randomWords) internal override  {
        // check

        // effects
        uint256 winnerIndex = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[winnerIndex];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0); // reset players array
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);

        // interactions
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    function getEntranceFee() external view returns (uint) {
        return i_entranceFee;
    }

    function getInterval() external view returns (uint) {
        return i_interval;
    }

    function getVrfCoordinator() external view returns (address) {
        return address(s_vrfCoordinator);
    }

    function getGasLane() external view returns (bytes32) {
        return i_keyHash;
    }
    
    function getCallbackGasLimit() external view returns (uint32) {
        return i_callbackGasLimit;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

}