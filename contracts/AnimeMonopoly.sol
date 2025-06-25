// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AnimeMonopoly is ERC721URIStorage, Ownable {
    IERC20 public animeToken;
    uint256 public playerCount;
    uint256 public constant COMMISSION_PERCENT = 5; // 0.5% expressed as tenths of percent
    uint256 public constant COMMISSION_DIVISOR = 1000;

    struct Tile {
        uint8 color;
        address[] owners;
        uint256 basePrice;
        uint256 priceStep;
    }

    Tile[] public tiles;
    mapping(uint256 => uint256) public playerPosition; // tokenId => tile index
    mapping(uint256 => uint256) public playerScore; // tokenId => score

    constructor(IERC20 _animeToken) ERC721("AnimeMonopolyPlayer", "AMP") Ownable(msg.sender) {
        animeToken = _animeToken;
        // create a simple board with 10 tiles as example
        for (uint8 i = 0; i < 10; i++) {
            tiles.push(Tile({color: i % 3, owners: new address[](0), basePrice: 1 ether, priceStep: 0.1 ether}));
        }
    }

    function joinGame() external {
        uint256 tokenId = ++playerCount;
        _mint(msg.sender, tokenId);
        playerPosition[tokenId] = 0;
        playerScore[tokenId] = 0;
    }

    function setAnimeToken(IERC20 token) external onlyOwner {
        animeToken = token;
    }

    function buyCity(uint256 tileId, uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "not owner of player");
        Tile storage tile = tiles[tileId];
        uint256 price = tile.basePrice + tile.priceStep * tile.owners.length;
        uint256 commission = (price * COMMISSION_PERCENT) / COMMISSION_DIVISOR;
        require(animeToken.transferFrom(msg.sender, owner(), commission), "commission fail");
        require(animeToken.transferFrom(msg.sender, address(this), price - commission), "payment fail");
        tile.owners.push(msg.sender);
        playerScore[tokenId] += price;
    }

    function getTileOwners(uint256 tileId) external view returns (address[] memory) {
        return tiles[tileId].owners;
    }
}
