// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract AnimeMonopoly is ERC721, ERC721Enumerable, Ownable, ReentrancyGuard {
    IERC20 public animeToken;
    uint256 public constant TOTAL_TILES = 40;
    uint256 public constant COMMISSION_RATE = 50; // 0.5%
    uint256 public constant TAX_FLAT_FEE = 10 * 1e18;
    uint256 public constant BUNKER_RENT = 3 * 1e18;
    uint256 public constant BUNKER_COST = 50 * 1e18;
    uint256 public constant BUNKER_DAMAGE_COOLDOWN = 60;
    address public treasury;
    bool public initialized;

    enum TileType { City, Jail, Tax, Bunker }
    enum ColorGroup { Red, Blue, Green, Yellow, Purple, Orange }

    struct Tile {
        TileType tileType;
        uint256 tileId;
        uint256 basePrice;
        ColorGroup colorGroup;
        uint256[] owners;
        mapping(uint256 => uint256) units;
        address bunkerOwner;
        uint256 lastDamageTime;
    }

    struct PlayerState {
        uint256 tokenId;
        uint256 position;
        uint256 score;
        uint256 jailUntil;
        bool frozen;
    }

    mapping(uint256 => PlayerState) public playerStates;
    mapping(uint256 => Tile) public board;
    mapping(address => uint256) public addressToTokenId;
    uint256 public nextTokenId = 1;

    mapping(address => bytes32) public diceCommitments;
    mapping(address => uint256) public diceRevealDeadline;
    mapping(uint256 => bool) public scoreRewardClaimed;

    event PlayerJoined(address indexed player, uint256 tokenId);
    event PlayerMoved(uint256 indexed tokenId, uint256 from, uint256 to);
    event PropertyBought(uint256 indexed tokenId, uint256 tileId, uint256 units);
    event RentPaid(uint256 indexed tokenId, uint256 tileId, uint256 amount);
    event JailEntered(uint256 indexed tokenId);
    event JailExited(uint256 indexed tokenId, string method);
    event TaxPaid(uint256 indexed tokenId, uint256 amount, string method);
    event BunkerInteracted(uint256 indexed tokenId, string action);
    event ScoreUpdated(uint256 indexed tokenId, uint256 newScore);
    event ScoreRewardClaimed(uint256 indexed tokenId);

    constructor(address _animeToken) ERC721("AnimeMonopolyPlayer", "AMP") {
        animeToken = IERC20(_animeToken);
        treasury = msg.sender;
    }

    function initializeBoard() external onlyOwner {
        require(!initialized, "Already initialized");
        for (uint256 i = 0; i < TOTAL_TILES; i++) {
            Tile storage tile = board[i];
            tile.tileId = i;
            if (i % 10 == 0) tile.tileType = TileType.Jail;
            else if (i % 15 == 0) tile.tileType = TileType.Tax;
            else if (i % 7 == 0) tile.tileType = TileType.Bunker;
            else tile.tileType = TileType.City;
            tile.basePrice = 10 * 1e18 + (i % 5) * 2 * 1e18;
            tile.colorGroup = ColorGroup(i % 6);
        }
        initialized = true;
    }

    function joinGame() external nonReentrant {
        require(addressToTokenId[msg.sender] == 0, "Already joined");
        uint256 tokenId = nextTokenId++;
        _safeMint(msg.sender, tokenId);
        addressToTokenId[msg.sender] = tokenId;
        playerStates[tokenId] = PlayerState(tokenId, 0, 0, 0, false);
        emit PlayerJoined(msg.sender, tokenId);
    }

    function commitDice(bytes32 commitment) external {
        require(ownerOf(addressToTokenId[msg.sender]) == msg.sender, "Not your player");
        diceCommitments[msg.sender] = commitment;
        diceRevealDeadline[msg.sender] = block.timestamp + 300;
    }

    function revealDice(uint256 nonce) external nonReentrant {
        bytes32 commitment = diceCommitments[msg.sender];
        require(commitment != 0, "No commit");
        require(block.timestamp <= diceRevealDeadline[msg.sender], "Reveal expired");
        require(keccak256(abi.encodePacked(msg.sender, nonce)) == commitment, "Invalid reveal");

        uint256 roll = (uint256(keccak256(abi.encodePacked(nonce, blockhash(block.number - 1)))) % 6) + 1;
        diceCommitments[msg.sender] = 0;
        diceRevealDeadline[msg.sender] = 0;

        uint256 tokenId = addressToTokenId[msg.sender];
        if (block.timestamp < playerStates[tokenId].jailUntil) {
            if (roll > 4) {
                playerStates[tokenId].jailUntil = 0;
                emit JailExited(tokenId, "roll");
                movePlayer(msg.sender, roll);
            } else {
                revert("Failed to escape jail with dice roll");
            }
        } else {
            movePlayer(msg.sender, roll);
        }
    }

    function payToExitJail() external nonReentrant {
        uint256 tokenId = addressToTokenId[msg.sender];
        require(block.timestamp < playerStates[tokenId].jailUntil, "Not in jail");
        uint256 fee = 5 * 1e18;
        require(animeToken.transferFrom(msg.sender, treasury, fee), "Payment failed");
        playerStates[tokenId].jailUntil = 0;
        emit JailExited(tokenId, "payment");
    }

    function movePlayer(address player, uint256 steps) internal {
        uint256 tokenId = addressToTokenId[player];
        PlayerState storage state = playerStates[tokenId];
        require(!state.frozen, "Frozen");
        require(block.timestamp >= state.jailUntil, "In jail");

        uint256 oldPos = state.position;
        uint256 newPos = (oldPos + steps) % TOTAL_TILES;
        state.position = newPos;

        Tile storage tile = board[newPos];

        if (tile.tileType == TileType.City) {
            handleCity(tile, tokenId);
        } else if (tile.tileType == TileType.Jail) {
            state.jailUntil = block.timestamp + 60;
            emit JailEntered(tokenId);
        } else if (tile.tileType == TileType.Tax) {
            uint256 balance = animeToken.balanceOf(player);
            uint256 percentTax = (balance * 30) / 100;
            if (animeToken.allowance(player, address(this)) >= percentTax && animeToken.balanceOf(player) >= percentTax) {
                require(animeToken.transferFrom(player, treasury, percentTax), "Percent tax fail");
                emit TaxPaid(tokenId, percentTax, "percentage");
            } else if (animeToken.allowance(player, address(this)) >= TAX_FLAT_FEE && animeToken.balanceOf(player) >= TAX_FLAT_FEE) {
                require(animeToken.transferFrom(player, treasury, TAX_FLAT_FEE), "Flat tax fail");
                emit TaxPaid(tokenId, TAX_FLAT_FEE, "flat");
            } else {
                state.frozen = true;
            }
        } else if (tile.tileType == TileType.Bunker) {
            emit BunkerInteracted(tokenId, "landed");
        }

        emit PlayerMoved(tokenId, oldPos, newPos);
    }

    function ownsAllColorGroup(ColorGroup group, uint256 tokenId) public view returns (bool) {
        for (uint256 i = 0; i < TOTAL_TILES; i++) {
            Tile storage tile = board[i];
            if (tile.tileType == TileType.City && tile.colorGroup == group) {
                bool owns = false;
                for (uint256 j = 0; j < tile.owners.length; j++) {
                    if (tile.owners[j] == tokenId) {
                        owns = true;
                        break;
                    }
                }
                if (!owns) {
                    return false;
                }
            }
        }
        return true;
    }

    function handleCity(Tile storage tile, uint256 tokenId) internal {
        address player = ownerOf(tokenId);
        uint256 unitPrice = tile.basePrice + tile.owners.length * 1e18;
        require(animeToken.transferFrom(player, treasury, unitPrice), "Buy fail");
        tile.owners.push(tokenId);
        tile.units[tokenId] += 1;

        uint256 rent = unitPrice / 10;
        bool hasBonus = ownsAllColorGroup(tile.colorGroup, tokenId);
        if (hasBonus) {
            rent = (rent * 3) / 2;
        }
        uint256 split = rent / tile.owners.length;
        for (uint256 i = 0; i < tile.owners.length; i++) {
            uint256 ownerId = tile.owners[i];
            address ownerAddr = ownerOf(ownerId);
            if (ownerAddr != player) {
                animeToken.transferFrom(player, ownerAddr, split);
                emit RentPaid(tokenId, tile.tileId, split);
            }
        }

        playerStates[tokenId].score += unitPrice;
        emit PropertyBought(tokenId, tile.tileId, 1);
        emit ScoreUpdated(tokenId, playerStates[tokenId].score);
    }

    function payTaxFlatFee() external nonReentrant {
        uint256 tokenId = addressToTokenId[msg.sender];
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(!playerStates[tokenId].frozen, "Already frozen");
        require(animeToken.transferFrom(msg.sender, treasury, TAX_FLAT_FEE), "Flat tax failed");
        emit TaxPaid(tokenId, TAX_FLAT_FEE, "flat");
    }

    function interactWithBunker(uint256 tileId, string calldata action) external nonReentrant {
        uint256 tokenId = addressToTokenId[msg.sender];
        Tile storage tile = board[tileId];
        require(tile.tileType == TileType.Bunker, "Not a bunker tile");

        if (keccak256(bytes(action)) == keccak256("rent")) {
            require(animeToken.transferFrom(msg.sender, tile.bunkerOwner, BUNKER_RENT), "Rent fail");
            emit BunkerInteracted(tokenId, "rent");
        } else if (keccak256(bytes(action)) == keccak256("buy")) {
            require(tile.bunkerOwner == address(0), "Already owned");
            require(animeToken.transferFrom(msg.sender, treasury, BUNKER_COST), "Buy fail");
            tile.bunkerOwner = msg.sender;
            emit BunkerInteracted(tokenId, "buy");
        } else if (keccak256(bytes(action)) == keccak256("damage")) {
            require(block.timestamp >= tile.lastDamageTime + BUNKER_DAMAGE_COOLDOWN, "Cooldown");
            tile.lastDamageTime = block.timestamp;
            emit BunkerInteracted(tokenId, "damage");
        } else {
            revert("Invalid action");
        }
    }

    function claimScoreReward() external nonReentrant {
        uint256 tokenId = addressToTokenId[msg.sender];
        require(!scoreRewardClaimed[tokenId], "Already claimed");
        uint256 score = playerStates[tokenId].score;
        require(score >= 100 * 1e18, "Not enough score");
        uint256 reward = score / 10;
        scoreRewardClaimed[tokenId] = true;
        require(animeToken.transfer(msg.sender, reward), "Reward transfer failed");
        emit ScoreRewardClaimed(tokenId);
    }

    function getPlayerScore(uint256 tokenId) external view returns (uint256) {
        return playerStates[tokenId].score;
    }

    function getPlayerRank(uint256 tokenId) external view returns (uint256 rank) {
        uint256 playerScore = playerStates[tokenId].score;
        rank = 1;
        for (uint256 i = 1; i < nextTokenId; i++) {
            if (i != tokenId && playerStates[i].score > playerScore) {
                rank++;
            }
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
