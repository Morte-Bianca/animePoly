// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AnimeMonopoly is ERC721Enumerable, Ownable, ReentrancyGuard {
    IERC20 public animeToken;
    uint256 public constant TOTAL_TILES = 21;
    uint256 public constant COMMISSION_RATE = 500; // 5%
    uint256 public constant BAIL_COST = 1 ether;
    uint256 public constant BRIBE_COST = 0.8 ether;
    uint256 public constant BUNKER_INITIAL_PRICE = 0.5 ether;
    uint256 public constant BUNKER_PRICE_INCREMENT = 0.1 ether; // increment factor for exponential pricing
    uint256 public constant BUNKER_RENT = 0.05 ether;
    uint256 public constant BUNKER_DAMAGE_COOLDOWN = 60;
    uint256 public constant TAX_ROLL_COOLDOWN = 5;
    uint256 public constant TAX_POINTS_PER_ANIME = 100;
    uint256 public constant BURN_RETURN_RATE = 8000; // 80% (scaled by 10000)
    uint256 private constant MULTIPLIER_BASE = 100;
    uint256 private constant DECIMALS = 1e18;
    address public treasury;
    bool public initialized;

    enum TileType { City, Jail, Tax, Bunker }
    enum ColorGroup {
        Red,
        Brown,
        Orange,
        LightGreen,
        Green,
        Blue
    }

    enum Vehicle { Bike, Car, Boat, Jet, Rocket }

    struct Tile {
        TileType tileType;
        uint256 refId; // city id for cities
    }

    struct City {
        string name;
        ColorGroup set;
        uint256 basePrice;
        uint256 priceIncrement; // exponential factor increment (scaled by 1e18)
        uint256 baseRent;
        uint8 radiation; // 0-5
        uint256 totalUnits;
        mapping(uint256 => uint256) units;
        mapping(uint256 => uint256) unitCost;
        uint256 contributions;
        uint256 sabotage;
    }

    struct Bunker {
        address owner;
        uint256 price; // current purchase price
        uint256 health;
        uint256 lastDamageTime;
    }

    struct PlayerState {
        uint256 tokenId;
        uint256 position;
        uint256 lastRoll;
        uint256 jailUntil;
        bool needsTaxAction;
        uint256 taxPoints;
    }

    mapping(uint256 => PlayerState) public playerStates;
    mapping(uint256 => Tile) public board;
    mapping(uint256 => City) public cities;
    Bunker public bunker;
    mapping(address => uint256) public addressToTokenId;
    uint256 public nextTokenId = 1;

    mapping(address => bytes32) public diceCommitments;
    mapping(address => uint256) public diceRevealDeadline;

    event PlayerJoined(address indexed player, uint256 tokenId);
    event PlayerMoved(uint256 indexed tokenId, uint256 from, uint256 to);
    event PropertyBought(uint256 indexed tokenId, uint256 tileId, uint256 units);
    event RentPaid(uint256 indexed tokenId, uint256 tileId, uint256 amount);
    event JailEntered(uint256 indexed tokenId);
    event JailExited(uint256 indexed tokenId, string method);
    event TaxPaid(uint256 indexed tokenId, uint256 amount, string method);
    event BunkerInteracted(uint256 indexed tokenId, string action);
    event TaxActionRequired(uint256 indexed tokenId);

    constructor(address _animeToken) ERC721("AnimeMonopolyPlayer", "AMP") Ownable(msg.sender) {
        animeToken = IERC20(_animeToken);
        treasury = msg.sender;
    }

    function initializeBoard() external onlyOwner {
        require(!initialized, "Already initialized");

        string[18] memory names = [
            "Baghdad",
            "Caracas",
            "San Francisco",
            "Pyongyang",
            "Karachi",
            "Jakarta",
            "Rome",
            "Buenos Aires",
            "Istanbul",
            "Barcelona",
            "Paris",
            "London",
            "Seoul",
            "Zurich",
            "New York",
            "Dubai",
            "Singapore",
            "Tokyo"
        ];

        ColorGroup[18] memory sets = [
            ColorGroup.Red,
            ColorGroup.Red,
            ColorGroup.Red,
            ColorGroup.Brown,
            ColorGroup.Brown,
            ColorGroup.Brown,
            ColorGroup.Orange,
            ColorGroup.Orange,
            ColorGroup.Orange,
            ColorGroup.LightGreen,
            ColorGroup.LightGreen,
            ColorGroup.LightGreen,
            ColorGroup.Green,
            ColorGroup.Green,
            ColorGroup.Green,
            ColorGroup.Blue,
            ColorGroup.Blue,
            ColorGroup.Blue
        ];

        uint256[18] memory prices = [
            uint256(0.25 ether),
            uint256(0.25 ether),
            uint256(0.25 ether),
            uint256(0.5 ether),
            uint256(0.5 ether),
            uint256(0.5 ether),
            uint256(1 ether),
            uint256(1 ether),
            uint256(1 ether),
            uint256(1 ether),
            uint256(1 ether),
            uint256(1 ether),
            uint256(2 ether),
            uint256(2 ether),
            uint256(2 ether),
            uint256(4 ether),
            uint256(4 ether),
            uint256(4 ether)
        ];

        uint256[18] memory increments = [
            uint256(0.001 ether),
            uint256(0.001 ether),
            uint256(0.001 ether),
            uint256(0.002 ether),
            uint256(0.002 ether),
            uint256(0.002 ether),
            uint256(0.005 ether),
            uint256(0.005 ether),
            uint256(0.005 ether),
            uint256(0.005 ether),
            uint256(0.005 ether),
            uint256(0.005 ether),
            uint256(0.01 ether),
            uint256(0.01 ether),
            uint256(0.01 ether),
            uint256(0.05 ether),
            uint256(0.05 ether),
            uint256(0.05 ether)
        ];

        uint256[18] memory rents = [
            uint256(0.01 ether),
            uint256(0.01 ether),
            uint256(0.01 ether),
            uint256(0.02 ether),
            uint256(0.02 ether),
            uint256(0.02 ether),
            uint256(0.05 ether),
            uint256(0.05 ether),
            uint256(0.05 ether),
            uint256(0.05 ether),
            uint256(0.05 ether),
            uint256(0.05 ether),
            uint256(0.1 ether),
            uint256(0.1 ether),
            uint256(0.1 ether),
            uint256(0.2 ether),
            uint256(0.2 ether),
            uint256(0.2 ether)
        ];

        uint256 cityIndex = 0;
        for (uint256 i = 0; i < TOTAL_TILES; i++) {
            Tile storage t = board[i];
            if (i == 3) {
                t.tileType = TileType.Jail;
            } else if (i == 10) {
                t.tileType = TileType.Tax;
            } else if (i == 14) {
                t.tileType = TileType.Bunker;
            } else {
                t.tileType = TileType.City;
                t.refId = cityIndex;
                City storage c = cities[cityIndex];
                c.name = names[cityIndex];
                c.set = sets[cityIndex];
                c.basePrice = prices[cityIndex];
                c.priceIncrement = increments[cityIndex];
                c.baseRent = rents[cityIndex];
                c.radiation = 5;
                cityIndex++;
            }
        }

        bunker.price = BUNKER_INITIAL_PRICE;
        bunker.health = 50000;

        initialized = true;
    }

    function joinGame() external nonReentrant {
        require(addressToTokenId[msg.sender] == 0, "Already joined");
        uint256 tokenId = nextTokenId++;
        _safeMint(msg.sender, tokenId);
        addressToTokenId[msg.sender] = tokenId;
        playerStates[tokenId] = PlayerState({
            tokenId: tokenId,
            position: 0,
            lastRoll: 0,
            jailUntil: 0,
            needsTaxAction: false,
            taxPoints: 0
        });
        emit PlayerJoined(msg.sender, tokenId);
    }

    function commitDice(bytes32 commitment) external {
        require(ownerOf(addressToTokenId[msg.sender]) == msg.sender, "Not your player");
        uint256 tokenId = addressToTokenId[msg.sender];
        PlayerState storage state = playerStates[tokenId];
        require(block.timestamp >= state.lastRoll + TAX_ROLL_COOLDOWN, "Wait to roll");
        require(!state.needsTaxAction, "Handle tax first");
        require(block.timestamp >= state.jailUntil, "In jail");
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
        playerStates[tokenId].lastRoll = block.timestamp;
        movePlayer(msg.sender, roll);
    }

    function payBail() external nonReentrant {
        uint256 tokenId = addressToTokenId[msg.sender];
        require(block.timestamp < playerStates[tokenId].jailUntil, "Not in jail");
        require(animeToken.transferFrom(msg.sender, treasury, BAIL_COST), "bail fail");
        playerStates[tokenId].jailUntil = 0;
        _addTaxPoints(tokenId, BAIL_COST);
        emit JailExited(tokenId, "bail");
    }

    function attemptBribe(uint256 nonce) external nonReentrant {
        uint256 tokenId = addressToTokenId[msg.sender];
        require(block.timestamp < playerStates[tokenId].jailUntil, "Not in jail");
        require(animeToken.transferFrom(msg.sender, treasury, BRIBE_COST), "bribe fail");
        uint256 rand = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), nonce, msg.sender))) % 100;
        _addTaxPoints(tokenId, BRIBE_COST);
        if (rand < 40) {
            playerStates[tokenId].jailUntil = 0;
            emit JailExited(tokenId, "bribe");
        }
    }

    function movePlayer(address player, uint256 steps) internal {
        uint256 tokenId = addressToTokenId[player];
        PlayerState storage state = playerStates[tokenId];
        require(!state.needsTaxAction, "Pending tax");
        require(block.timestamp >= state.jailUntil, "In jail");

        uint256 oldPos = state.position;
        uint256 newPos = (oldPos + steps) % TOTAL_TILES;
        state.position = newPos;

        Tile storage tile = board[newPos];

        if (tile.tileType == TileType.City) {
            handleCity(tile.refId, tokenId);
        } else if (tile.tileType == TileType.Jail) {
            state.jailUntil = block.timestamp + _jailWaitTime(tokenId);
            emit JailEntered(tokenId);
        } else if (tile.tileType == TileType.Tax) {
            state.needsTaxAction = true;
            emit TaxActionRequired(tokenId);
        } else if (tile.tileType == TileType.Bunker) {
            emit BunkerInteracted(tokenId, "landed");
        }

        emit PlayerMoved(tokenId, oldPos, newPos);
    }


    function handleCity(uint256 cityId, uint256 tokenId) internal {
        City storage city = cities[cityId];
        address player = ownerOf(tokenId);

        if (city.totalUnits > 0 && city.units[tokenId] == 0) {
            uint256 rent = _calcRent(cityId);
            uint256 vehicleMult = _vehicleMultiplier(tokenId);
            uint256 totalDue = rent * vehicleMult;
            require(animeToken.transferFrom(player, treasury, totalDue), "rent fail");
            _addTaxPoints(tokenId, totalDue);
            _distributeRent(cityId, totalDue);
            emit RentPaid(tokenId, cityId, totalDue);
        }
    }

    function mintUnit() external nonReentrant {
        uint256 tokenId = addressToTokenId[msg.sender];
        PlayerState storage state = playerStates[tokenId];
        Tile storage t = board[state.position];
        require(t.tileType == TileType.City, "Not on city");
        uint256 cityId = t.refId;
        City storage city = cities[cityId];
        uint256 price = _currentPrice(cityId);
        require(animeToken.transferFrom(msg.sender, treasury, price), "pay fail");
        city.totalUnits += 1;
        city.units[tokenId] += 1;
        city.unitCost[tokenId] += price;
        city.contributions += price * TAX_POINTS_PER_ANIME;
        _addTaxPoints(tokenId, price);
        _updateRadiation(cityId);
        emit PropertyBought(tokenId, cityId, city.units[tokenId]);
    }

    function burnUnit(uint256 cityId) external nonReentrant {
        uint256 tokenId = addressToTokenId[msg.sender];
        City storage city = cities[cityId];
        require(city.units[tokenId] > 0, "No units");
        uint256 avgCost = city.unitCost[tokenId] / city.units[tokenId];
        uint256 refund = (avgCost * BURN_RETURN_RATE) / 10000;
        city.units[tokenId] -= 1;
        city.unitCost[tokenId] -= avgCost;
        city.totalUnits -= 1;
        require(animeToken.transfer(msg.sender, refund), "refund fail");
    }

    function _distributeRent(uint256 cityId, uint256 totalRent) internal {
        City storage city = cities[cityId];
        for (uint256 i = 1; i < nextTokenId; i++) {
            uint256 units = city.units[i];
            if (units > 0) {
                uint256 share = (totalRent * units) / city.totalUnits;
                uint256 multiplier = 100 + 5 * _completedSets(i);
                share = (share * multiplier) / 100;
                animeToken.transfer(ownerOf(i), share);
            }
        }
        city.contributions += totalRent * TAX_POINTS_PER_ANIME;
        _updateRadiation(cityId);
    }

    function _calcRent(uint256 cityId) internal view returns (uint256) {
        City storage city = cities[cityId];
        uint256 mult;
        if (city.radiation == 0) mult = 400;
        else if (city.radiation == 1) mult = 160;
        else if (city.radiation == 2) mult = 140;
        else if (city.radiation == 3) mult = 120;
        else if (city.radiation == 4) mult = 110;
        else mult = 100;
        return (city.baseRent * mult) / 100;
    }

    function _currentPrice(uint256 cityId) internal view returns (uint256) {
        City storage city = cities[cityId];
        uint256 factor = DECIMALS + city.priceIncrement;
        uint256 multiplier = _pow(factor, city.totalUnits, DECIMALS);
        return (city.basePrice * multiplier) / DECIMALS;
    }

    function _vehicleMultiplier(uint256 tokenId) internal view returns (uint256) {
        uint256 count;
        for (uint256 i = 0; i < 18; i++) {
            count += cities[i].units[tokenId];
        }
        if (count >= 100) return 10;
        if (count >= 60) return 4;
        if (count >= 40) return 3;
        if (count >= 20) return 2;
        return 1;
    }

    function _jailWaitTime(uint256 tokenId) internal view returns (uint256) {
        uint256 mult = _vehicleMultiplier(tokenId);
        if (mult == 1) return 12 hours;
        if (mult == 2) return 18 hours;
        if (mult == 3) return 24 hours;
        if (mult == 4) return 36 hours;
        return 48 hours;
    }

    function _completedSets(uint256 tokenId) internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 s = 0; s < 6; s++) {
            bool ownsAll = true;
            for (uint256 i = 0; i < 18; i++) {
                if (cities[i].set == ColorGroup(s)) {
                    if (cities[i].units[tokenId] == 0) {
                        ownsAll = false;
                        break;
                    }
                }
            }
            if (ownsAll) count++;
        }
        return count;
    }

    function _updateRadiation(uint256 cityId) internal {
        City storage city = cities[cityId];
        int256 score = int256(city.contributions) - int256(city.sabotage);
        uint8 level = 5;
        if (score >= 100000) level = 0;
        else if (score >= 60000) level = 1;
        else if (score >= 40000) level = 2;
        else if (score >= 20000) level = 3;
        else if (score >= 10000) level = 4;
        city.radiation = level;
    }

    function _addTaxPoints(uint256 tokenId, uint256 animeAmount) internal {
        playerStates[tokenId].taxPoints += (animeAmount / 1 ether) * TAX_POINTS_PER_ANIME;
    }

    function fileTaxes() external nonReentrant {
        uint256 tokenId = addressToTokenId[msg.sender];
        PlayerState storage state = playerStates[tokenId];
        require(state.needsTaxAction, "No action required");
        require(board[state.position].tileType == TileType.Tax, "Not at tax");
        state.needsTaxAction = false;
        uint256 rand = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender))) % 100;
        if (rand < 50) {
            state.taxPoints *= 2;
            emit TaxPaid(tokenId, 0, "doubled");
        } else {
            state.taxPoints = 0;
            emit TaxPaid(tokenId, 0, "lost");
        }
    }

    function useTaxPoints(uint256 cityId, bool contribute, uint256 amount) external nonReentrant {
        uint256 tokenId = addressToTokenId[msg.sender];
        PlayerState storage state = playerStates[tokenId];
        require(state.taxPoints >= amount, "Insufficient points");
        if (state.needsTaxAction) {
            require(board[state.position].tileType == TileType.Tax, "Not at tax");
            state.needsTaxAction = false;
        }
        if (contribute) {
            cities[cityId].contributions += amount;
        } else {
            cities[cityId].sabotage += amount;
        }
        state.taxPoints -= amount;
        _updateRadiation(cityId);
        emit TaxPaid(tokenId, amount, contribute ? "contribute" : "sabotage");
    }

    function interactWithBunker(string calldata action) external nonReentrant {
        uint256 tokenId = addressToTokenId[msg.sender];
        require(board[playerStates[tokenId].position].tileType == TileType.Bunker, "Not on bunker");

        if (keccak256(bytes(action)) == keccak256("rent")) {
            require(bunker.owner != address(0), "Unowned");
            require(animeToken.transferFrom(msg.sender, bunker.owner, BUNKER_RENT), "Rent fail");
            _addTaxPoints(tokenId, BUNKER_RENT);
            emit BunkerInteracted(tokenId, "rent");
        } else if (keccak256(bytes(action)) == keccak256("buy")) {
            require(animeToken.transferFrom(msg.sender, treasury, bunker.price), "Buy fail");
            bunker.owner = msg.sender;
            bunker.price = (bunker.price * (DECIMALS + BUNKER_PRICE_INCREMENT)) / DECIMALS;
            _addTaxPoints(tokenId, bunker.price);
            emit BunkerInteracted(tokenId, "buy");
        } else if (keccak256(bytes(action)) == keccak256("damage")) {
            require(block.timestamp >= bunker.lastDamageTime + BUNKER_DAMAGE_COOLDOWN, "Cooldown");
            bunker.lastDamageTime = block.timestamp;
            require(playerStates[tokenId].taxPoints >= 1, "No tax points");
            bunker.health -= 1;
            playerStates[tokenId].taxPoints -= 1;
            emit BunkerInteracted(tokenId, "damage");
        } else {
            revert("Invalid action");
        }
    }

    function _pow(uint256 base, uint256 exp, uint256 scale) internal pure returns (uint256 result) {
        result = scale;
        while (exp > 0) {
            if (exp % 2 == 1) {
                result = (result * base) / scale;
            }
            base = (base * base) / scale;
            exp /= 2;
        }
    }



    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
