// SPDX-License-Identifier: UNLICENSED  

pragma solidity ^0.8.0;



/**
 * @dev Contract module which provides a basic access control mechanism, where there is an account (an owner) that can be granted exclusive access to specific functions.
 * By default, the owner account will be the one that deploys the contract. This can later be changed with transferOwnership.
 */
import "@openzeppelin/contracts/access/Ownable.sol";  


/**
 * @dev ERC20 interface
 */
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/**
 * @dev Helps contracts guard against reentrancy attacks.
 *      If you mark a function `nonReentrant`, you should also mark it `external`.
 */
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";


/**
 * @dev Contract module which provides verifiable randomness 
 */
import "https://github.com/smartcontractkit/chainlink/blob/master/contracts/src/v0.8/VRFConsumerBase.sol"; 





/**
 * @title FiftyFifty
 * @dev Contract, inheriting from Ownable.sol and VRFConsumerBase.sol, for player vs player betting.
 */
contract FiftyFork is Ownable, VRFConsumerBase, ReentrancyGuard {  
    
    
    
    // VARIABLES //
    
    bytes32 public keyHash;
    uint256 public fee;
    uint256 public randomResult;
    
    uint public commissionBalance;
    uint public commissionPercentage;
    uint public affiliateCommissionPercentage;
    uint public minimumBetSize;
    
    uint private gameID;
    
    IERC20 public token;
                        
    
    
    
    
    // CONSTRUCTOR //
    
    /**
     * @dev  Chainlink VRF set up for Polygon Mumbai Test Network -- For main net deployment see [https://docs.chain.link/docs/vrf-contracts/]
     * 
     */
    constructor(IERC20 _token) Ownable() VRFConsumerBase(0x8C7382F9D8f56b33781fE506E897a4F1e2d17255,  // VRF Coordinator for Polygon Mumbai Test Network ONLY
                                            0x326C977E6efc84E512bB9C30f76E30c160eD06FB  // LINK Token address on Polygon Mumbai Test Network ONLY
                                            )  
    {
        
        keyHash = 0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4; // for Polygon Mumbai Test Network ONLY
        fee = 0.0001 * 10 ** 18; // 0.0001 LINK for Polygon ONLY
        
        
        ////////////////////////////////////////////
        
        commissionBalance = 0;
        commissionPercentage = 6;
        affiliateCommissionPercentage = 2;
        minimumBetSize = 1*10**9;      // 1 gwei
        gameID = 1;
        
        admin[msg.sender] = true; // set's contract owner address to also have admin privileges
    }
    
    
    
    // MODIFIERS //
    
    modifier onlyAdmin {
        require(admin[msg.sender] == true, "Only admins or contract owner can call this function.");
        _;
    }
    
    
    
    // STRUCTS //
    
    struct Game {
        
        uint betAmount;           // default 0
        address payable creator;  // default 0x address
        address payable joiner;   // default 0x address
        address payable winner;   // default 0x address
        bool liveGame;            // default false
        
    }
    
    struct Player {
        
        uint balance;           // default 0   (balance is only accrued through affiliate commission)
        uint gameCount;         // default 0
        uint totalBet;          // default 0
        uint totalWinnings;     // default 0
        uint winCount;          // default 0
        
    }
    
    
    
    // MAPPINGS //
    
    /**
     * @dev Maps gameID to struct 'Game'.
     */
    mapping(uint => Game) private game;
    
    /**
     * @dev Maps player address to struct Player.
     */
    mapping(address => Player) private player;
    
    
    /**
     * @dev Maps VRF's requestID to gameID.
     */
    mapping(bytes32 => uint) private requestIdToGameId;
    
    
    /**
     * @dev Maps new player address to address of player that referred them.
     */
    mapping(address => address) private referral;
    
    
    /**
     * @dev Maps address to boolean. Used for admin privilege
     */
    mapping(address => bool) private admin;
    
    
    
    
    // EVENTS //
    
    /**
     * @dev Emitted when Player 1 creates a game with ID '_gameID'
     * and deposit's amount '_betAmount' in to the smart contract
     */
    event GameCreated(uint gameID, uint betAmount);
    
    
    /**
     * @dev Emitted when Player 2 joins a game with ID '_gameID'
     * and deposit's amount 'betAmount[_gameID]' in to the smart contract
     */
    event GameJoined(uint gameID, uint betAmount);
    
    
    /**
     * @dev Emitted when winning player withdraws their winnings from the smart contract
     */
    event WinningsWithdrawn(uint gameID, uint commission, uint commissionBalance, uint winnings);
    
    
    /**
     * @dev Emitted when Player 1 (the game creator) withdraws their _betAmount from the smart contract
     */
    event BetCancelled(uint gameID, uint betAmount);
    
    
    /**
     * @dev Emitted when 'winner' fucntion declares a winner
     */
    event WinnerDeclared(uint gameID, address winner, uint randomResult);
    
    
    /**
     * @dev Emitted when a player withdraws tokens earned through affiliate commission
     */
    event CommissionWithdrawal(address playerAddress, uint amount);
    
    
    
    
    
    
 
    
    
    
    ////////////// PLAYER FUNCTIONS ///////////////
    
    
    /**
     * @dev Player 1 creates a game, depositing amount '_amount' of token tokens in to the smart contract.
     * 
     * Requires Player 1 to have pre-approved smart contract address to spend >= _amount of tokens using the approve() function of the token token contract.
     *
     * Emits a {GameCreated} event.
     */
    function createGame(uint _amount) external nonReentrant payable {
        
        require(game[gameID].betAmount == 0, "GameID already used.");
        require(_amount >= minimumBetSize, "Bet size less than minimum.");  // ensures betAmount >= minimumBetSize
        require((token.balanceOf(msg.sender)) >= _amount, "Insufficient funds.");
        require((token.allowance(msg.sender, address(this))) >= _amount, "Bet amount greater than allowance."); // ensures bet amount '_amount' is within allowance
        
        token.transferFrom(msg.sender, address(this), _amount);  // tranfers tokens from player's wallet to the smart contract
        
        player[msg.sender].gameCount += 1;
        player[msg.sender].totalBet += _amount;
        
        game[gameID].betAmount = _amount;
        game[gameID].creator = payable(msg.sender);
        game[gameID].liveGame = true;
        
        gameID += 1; // increments gameID counter for next game creation
        
        emit GameCreated(gameID, _amount);  // (uint gameID, uint betAmount)
    }
    
    
    /**
     * @dev Player 2 joins a game depositing amount 'game[_gameID].betAmount' equal to 'msg.value' in to the smart contract.
     * 
     * Emits a {gameJoined} event.
     * 
     * calls function to determine game winner
     */
    function joinGame(uint _gameID, uint _amount) external nonReentrant payable {
        
        require(game[_gameID].liveGame == true, "Game not live."); // ensures game is live
        require(_amount >= minimumBetSize, "Bet size less than minimum.");  // ensures betAmount >= minimumBetSize
        require(_amount == game[_gameID].betAmount, "Bet size differs");  // ensures betAmount is equal to game creator's
        require((token.allowance(msg.sender, address(this))) >= _amount, "Bet amount greater than website balance."); // ensures bet amount '_amount' is within allowance
        
        token.transferFrom(msg.sender, address(this), _amount); // tranfers tokens from player's wallet to the smart contract
        
        player[msg.sender].gameCount += 1;
        player[msg.sender].totalBet += _amount;
        
        game[_gameID].joiner = payable(msg.sender);
        
        emit GameJoined(_gameID, game[_gameID].betAmount);  // (uint gameID, uint betAmount)
        
        require(LINK.balanceOf(address(this)) >= fee, "Smart contract does not contain enough LINK to make VRF request.");
        requestIdToGameId[getRandomNumber()] = _gameID;
    }
    
    
    
    
    /**
     * @dev Player 1, the game creator, can withdraw their bet amount and cancel the game in the event no one joins.
     * 
     * Emits a {betCancelled} event.
     */
    function cancelBet(uint _gameID) external nonReentrant {
        
        require(game[_gameID].liveGame == true, "Game is not live");   // Ensures game is live
        require(game[_gameID].creator == msg.sender, "Must be game creator");   // Ensures function caller address is the game creators address
        require(game[_gameID].joiner == address(0), "Game has already commenced.");   // Ensures Player 2 hasn't joined the game
        
        game[_gameID].liveGame = false;  // sets game status to over
        
        player[msg.sender].gameCount -= 1;
        player[msg.sender].totalBet -= game[_gameID].betAmount;
        
        token.transfer(msg.sender, game[_gameID].betAmount);  // withdraws betAmount to the game creator
        
        emit BetCancelled(_gameID, game[_gameID].betAmount);  // (uint gameID, uint bebetAmount)
    }
    
    
    /**
     * @dev Winning player can withdraw their winnings.
     * 
     * Emits a {winningsWithdrawn} event.
     */
    function winningsWithdraw(uint _gameID) external nonReentrant payable {
        
        require(game[_gameID].winner != address(0), "Winner is yet to be determined."); // Ensures VRF callback has happend and winner has been decided 
        require(game[_gameID].winner == msg.sender, "Only the winner can withdraw winnings");  // ensures only winning address can withdraw winnings
        require(game[_gameID].liveGame == true, "Game not live");
        
        uint contractCommission = 0;
        uint affiliateCommission = 0;
        address referrer = referral[msg.sender];
        
        if (referrer != address(0)) {
            affiliateCommission = ((2*game[_gameID].betAmount*affiliateCommissionPercentage)/100); 
            player[referrer].balance += affiliateCommission;
    
            contractCommission = ((2*game[_gameID].betAmount*(commissionPercentage-affiliateCommissionPercentage))/100); 
            commissionBalance += contractCommission;
        }
        else {
            contractCommission = ((2*game[_gameID].betAmount*commissionPercentage)/100);  
            commissionBalance += contractCommission;
        }
        
        game[_gameID].liveGame = false; // sets game status to over
        
        uint winnings = (2*game[_gameID].betAmount)-(contractCommission + affiliateCommission);
        
        player[msg.sender].totalWinnings += winnings;
        player[msg.sender].winCount += 1;
        
        token.transfer(msg.sender, winnings);
        
          
        emit WinningsWithdrawn(_gameID, contractCommission, commissionBalance, winnings);  // (uint gameID, uint winnings)
    }
    
    
    /**
     * @dev Players can withdraw tokens earned through affiliate commission
     * 
     * Emits a {winningsWithdrawn} event.
     */
    function playerWithdraw(uint _amount) public nonReentrant {
        require(player[msg.sender].balance >= _amount, "Withdrawal amount greater than player balance of tokens held by this smart contract.");
        player[msg.sender].balance -= _amount;
        token.transfer(msg.sender, _amount);
        emit CommissionWithdrawal(msg.sender, _amount);
    }
    
    
    
    
    ///// LINK VRF FUNCTIONS ////
    
    // fucntion imported from VRFConsumerBase contract
    function getRandomNumber() public returns(bytes32 requestId) {
        return requestRandomness(keyHash, fee);
    }
    
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        randomResult = (randomness % 2) + 1; // result will either be '1' or '2'
        
        uint _gameID = requestIdToGameId[requestId];  // get's gameID from VRF requestID
        
        if (randomResult == 1) {
            game[_gameID].winner = game[_gameID].creator;
        }
        else if (randomResult == 2) {
            game[_gameID].winner = game[_gameID].joiner;
        } 
        
        
        emit WinnerDeclared(_gameID, game[_gameID].winner, randomResult);   // (uint gameID, address winner, uint randomResult)
    }
    
    
    
    
    
    ///// VIEW FUNCTIONS ////
    

    /**
     * @dev View amount of tokens the smart contract is allowed to spend on behalf of address '_address'
     */
    function viewAllowance(address _address) public view returns(uint) {
       return token.allowance(_address, address(this));
    }


    /**
     * @dev View winning address.
     * 
     * Free to call externally. Likley useful for when winning player is not the game creator and checks if they won their game.
     * 
     * Returns winner's address.
     */
    function viewWinner(uint _gameID) external view returns(address) {
        return game[_gameID].winner; 
    }
    
    
    /**
     * @dev View game creator.
     * 
     * Free to call externally. Used for validation purposes.
     * 
     * Returns game creator's address.
     */
    function viewGameCreator(uint _gameID) external view returns(address) {
        return game[_gameID].creator;
    }
    
    
    /**
     * @dev View game joiner address.
     * 
     * Free to call externally. Used for validation purposes.
     */
    function viewGameJoiner(uint _gameID) external view returns(address) {
        return game[_gameID].joiner;
    }
    
    
    /**
     * @dev View game bet amount.
     * 
     * Free to call externally. Used for validation purposes.
     */
    function viewGameBetAmount(uint _gameID) external view returns(uint) {
        return game[_gameID].betAmount;
    }
    
    
    /**
     * @dev View player balance. (Earned through commission only. Winnings are directly withdrawn.)
     */
    function viewPlayerBalance(address _address) external view returns(uint) {
        return player[_address].balance;
    }
    
    
    /**
     * @dev View player game count.
     */
    function viewPlayerGameCount(address _address) external view returns(uint) {
        return player[_address].gameCount;
    }
    
    
    /**
     * @dev View player win count.
     */
    function viewPlayerWinCount(address _address) external view returns(uint) {
        return player[_address].winCount;
    }
    
    
    /**
     * @dev View player's bet total
     */
    function viewPlayerTotalBet(address _address) external view returns(uint) {
        return player[_address].totalBet;
    }
    
    
    /**
     * @dev View player total winnings.
     */
    function viewPlayerTotalWinnings(address _address) external view returns(uint) {
        return player[_address].totalWinnings;
    }
    

    /**
     * @dev View contract LINK balance.
     * 
     */
    function viewLinkBalance() public view returns(uint) {
        return LINK.balanceOf(address(this)); 
    }
    
    
    
    

    
    
    
    
    /////////////// ADMIN FUNCTIONS ////////////////////
    
    
    /**
     * @dev Map a new player's address to the address of the player that refered them
     */
    function addReferral(address _newPlayer, address _referrer) public onlyAdmin {
        referral[_newPlayer] = _referrer;
    }
    
    
    /**
     * @dev Remove the map of a player's address to the address of the player that refered them
     * 
     * Note: requires address on player referred. Not the address of the referrer.
     */
    function removeReferral(address _player) public onlyAdmin {
        referral[_player] = address(0);
    }
    
    
    /**
     * @dev Set's the commission percentage. Must be a whole number.
     * 
     * Note: Only contract owner can call.
     *
     */
    function setCommissionPercentage(uint _commissionPercentage) public onlyAdmin {
        commissionPercentage = _commissionPercentage;
    }
    
    
    /**
     * @dev Set's the affiliate commission percentage. Must be a whole number.
     * 
     * Note: Only contract owner can call.
     *
     */
    function setAffiliateCommissionPercentage(uint _affiliateCommissionPercentage) public onlyAdmin {
        affiliateCommissionPercentage = _affiliateCommissionPercentage;
    }
    
    
    /**
     * @dev Set the minimum bet size. Unit: wei
     * 
     * Note: Only contract owner can call.
     */
    function setMinimumBetSize(uint _minimumBetSize) public onlyAdmin {
        minimumBetSize = _minimumBetSize;
    }
    
    
    
    /////////////// ONLY OWNER FUNCTIONS ////////////////////
    
    
    /**
     * @dev Adds new admin address
     */
    function addAdmin(address _newAdmin) public onlyOwner {
        admin[_newAdmin] = true;
    }
    
    
    /**
     * @dev Removes admin address
     */
    function removeAdmin(address _removeAddress) public onlyOwner {
        admin[_removeAddress] = false;
    }
    
    
    
    /**
     * @dev Withdraw amount '_amount' from smart contract to address '_to'. Unit: wei
     * 
     * Note: Only contract owner can call.
     */
    function withdrawContractCommission(uint _amount, address payable _to) public onlyOwner {
        
        require(_amount <= commissionBalance, "Withdrawal amount greater than balance.");
        
        commissionBalance -= _amount;
        
        
        token.transfer(_to, _amount);  // withdraws amount '_amount' to specified address '_to'
    }
    

    /**
     * @dev Withdraw amount '_amount' of LINK from smart contract to address '_to'. Unit: wei
     * 
     * Note: Only contract owner can call.
     */
    function withdrawLink(uint _amount, address payable _to) public onlyOwner {
        
        require(_amount <= LINK.balanceOf(address(this)), "Withdrawel amount greater than balance.");
        
        LINK.transfer(_to, _amount);  // withdraws amount '_amount' to specified address '_to'
        
    }
    
    
    
}


