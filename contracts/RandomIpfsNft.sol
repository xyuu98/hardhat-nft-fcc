// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error RandomIpfsNft__RangeOutOfRarity();
error RandomIpfsNft__NeedMoreETHSent();
error RandomIpfsNft__TransferFailed();

contract RandomIpfsNft is VRFConsumerBaseV2, ERC721URIStorage, Ownable {
    enum Rarity {
        common,
        rare,
        legendary
    }

    //Chainlink VRF 状态变量
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    //VRF 映射
    mapping(uint256 => address) public s_requstIdToSender;

    //NFT 状态变量
    uint256 public s_tokenCounter;
    uint256 internal constant MAX_CHANCE_VALUE = 100;
    string[] internal s_wingsTokenUris;
    uint256 internal immutable i_mintFee;

    // 事件
    event NftRequested(uint256 indexed requestId, address requester);
    event NftMinted(Rarity rarity, address minter);

    constructor(
        address VRFCoordinatorV2,
        uint64 subscriptionId,
        bytes32 gasLane,
        uint32 callbackGasLimit,
        string[3] memory wingsTokenUris,
        uint256 mintFee
    ) VRFConsumerBaseV2(VRFCoordinatorV2) ERC721("WINGS", "WS") {
        i_vrfCoordinator = VRFCoordinatorV2Interface(VRFCoordinatorV2);
        i_subscriptionId = subscriptionId;
        i_gasLane = gasLane;
        i_callbackGasLimit = callbackGasLimit;
        s_wingsTokenUris = wingsTokenUris;
        i_mintFee = mintFee;
    }

    function requestNft() public payable returns (uint256 requestId) {
        if (msg.value < i_mintFee) {
            revert RandomIpfsNft__NeedMoreETHSent();
        }
        requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        s_requstIdToSender[requestId] = msg.sender;
        emit NftRequested(requestId, msg.sender);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        address WingsOwner = s_requstIdToSender[requestId];
        uint256 newTokenId = s_tokenCounter;
        s_tokenCounter = s_tokenCounter + 1;

        uint256 moddedRng = randomWords[0] % MAX_CHANCE_VALUE;
        Rarity wingsRarity = getRarityFromModdedRng(moddedRng);

        _safeMint(WingsOwner, newTokenId);
        _setTokenURI(newTokenId, s_wingsTokenUris[uint256(wingsRarity)]);
        emit NftMinted(wingsRarity, WingsOwner);
    }

    function withdraw() public onlyOwner {
        uint256 amount = address(this).balance;
        (bool suc, ) = payable(msg.sender).call{value: amount}("");
        if (!suc) {
            revert RandomIpfsNft__TransferFailed();
        }
    }

    function getRarityFromModdedRng(uint256 moddedRng) public pure returns (Rarity) {
        uint256 cumulativeSum = 0;
        uint256[3] memory chanceArray = getChanceArray();

        for (uint256 i = 0; i < chanceArray.length; i++) {
            // common = 0 - 9  (10%)
            // rare = 10 - 39  (30%)
            // legendary = 40 - 99 (60%)
            if (moddedRng >= cumulativeSum && moddedRng < cumulativeSum + chanceArray[i]) {
                return Rarity(i);
            }
            cumulativeSum += chanceArray[i];
        }
        revert RandomIpfsNft__RangeOutOfRarity();
    }

    function getChanceArray() public pure returns (uint256[3] memory) {
        return [10, 30, MAX_CHANCE_VALUE];
    }

    function getMintFee() public view returns (uint256) {
        return i_mintFee;
    }

    function getWingsTokenUris(uint256 index) public view returns (string memory) {
        return s_wingsTokenUris[index];
    }

    function getTokenCounter() public view returns (uint256) {
        return s_tokenCounter;
    }
}
