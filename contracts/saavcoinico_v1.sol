pragma solidity ^0.4.13;

/*! Operations with safety checks that throw on error
 */
library SafeMath {
	function sub(uint256 a, uint256 b) internal constant returns (uint256) {
		assert(b <= a);
		return a - b;
	}

	function add(uint256 a, uint256 b) internal constant returns (uint256) {
		uint256 c = a + b;
		assert(c >= a);
		return c;
	}

	function mul(uint256 a, uint256 b) internal constant returns (uint256) {
		uint256 c = a * b;
		assert(a == 0 || c / a == b);
		return c;
	}

	function div(uint256 a, uint256 b) internal constant returns (uint256) {
		// assert(b > 0); // Solidity automatically throws when dividing by 0
		uint256 c = a / b;
		// assert(a == b * c + a % b); // There is no case in which this doesn't hold
		return c;
	}
}

/*!	Base for the contract to define the owner (or admin) account
	which will have exclusive rights to do admin operations on the
	token sale contract.

	Provides modifier onlyOwner
	The ownership can be changed with transferOwnership
 */
contract owned {
	address public owner;

	function owned() {
		owner = msg.sender;
	}

	modifier onlyOwner {
		require(msg.sender == owner);
		_;
	}

	function adminTransferOwnership(address newOwner) onlyOwner {
		owner = newOwner;
	}
}

/*!	Collect admin functions in contract inherited from owned
 */
contract admin is owned {

	/*!	Indication that sale is allowed
		Users can transfer Ether to contract address
		and receive tokens to their accounts (in balanceOf)
	 */
	bool public saleIsAllowed;

	/*!	Indication that sale is finished
		and users can trade/transfer tokens
	 */
	bool public transfersAreAllowed;

	/*!	Exchange rate for ETH/USD
		It will be used for token sale as token sale nominated in USD
	 */
	uint256 public usdForOneEth;

	/*!	Define the amount of SAAV per USD
		Fixed to 100 (100 SAAV = 1 USD)
	 */
	uint256 public saavPerUsd;

	/*!	Amount in USD which has effect for applying bonus
		If greater or equal this value, then bonus apply.
	 */
	uint256 public minimumUsdValueForBonus;

	/*!	Bonus amount in USD
	 */
	uint256 public bonusInUsd;

	/* ----------------------------- Methods ----------------------------- */

	/*!	Withdraw complete ether balance to owner
		Can run by "onlyOwner"
	 */
	function adminWithdrawAllEther() onlyOwner {
		owner.transfer(this.balance);
	}

	/*!	Withdraw specified ether balance to owner
		Can run by "onlyOwner"
	 */
	function adminWithdrawEther(uint value) onlyOwner {
		owner.transfer(value);
	}

	/*!	Start (or stop) the sale of tokens (by transfering Ether
		to the contract address).
		Can run by "onlyOwner"
	 */
	function adminSetSaleAllowed(bool value) onlyOwner {
		saleIsAllowed = value;
	}

	/*!	Start (or stop) the tokens transfers.
		Can run by "onlyOwner"
	 */
	function adminSetTransfersAllowed(bool value) onlyOwner {
		transfersAreAllowed = value;
	}

	/*!	Change the exchange rate for ETH/USD
	 */
	function adminSetUsdForOneEth(uint256 value) onlyOwner {
		usdForOneEth = value;
	}

	/*!	Change the amount of SAAV per USD
	 */
	function adminSetSaavPerUsd(uint256 value) onlyOwner {
		saavPerUsd = value;
	}

	/*!	Change the bonus amount in USD
	 */
	function adminSetBonusInUsd(uint256 value) onlyOwner {
		bonusInUsd = value;
	}

	/*!	Change the amount in USD which has effect for applying bonus
	 */
	function adminSetMinimumUsdValueForBonus(uint256 value) onlyOwner {
		minimumUsdValueForBonus = value;
	}

	/*!	Contructor
		Defaults:
			no sale,
			no transfers
			300 USD per ETH
	 */
	function admin() {
		saleIsAllowed = false;
		transfersAreAllowed = false;
		usdForOneEth = 300;
		saavPerUsd = 100;					// 100 SAAV per USD
		bonusInUsd = 100;					// 100 USD bonus
		minimumUsdValueForBonus = 500;		// Minimum 500 USD to get a bonus
	}
}

/*!	Definition of destination interface
	for contract that can be used for migration
 */
contract MigrationAgent {
    function migrateFrom(address from, uint256 value);
}

/*!	ERC20 standard API
 */
contract ERC20 {
	uint256 public totalSupply;

	function balanceOf(address who) constant returns (uint256);
	function allowance(address owner, address spender) constant returns (uint256);

	function transfer(address to, uint256 value) public returns (bool);
	function transferFrom(address from, address to, uint256 value) public returns (bool);
	function approve(address spender, uint256 value) public returns (bool);

	event Transfer(address indexed from, address indexed to, uint256 value);
	event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract SaavCoins is ERC20, admin {
	using SafeMath for uint256;

	string public name;
	string public symbol;
	uint8 public decimals;
	uint256 public decimalsMultiplier;

	//! A map with all balances
	mapping (address => uint256) public balances;

	//! A balance of the specified address
	function balanceOf(address owner) public constant returns (uint256 balance) {
		return balances[owner];
  	}

	//! A map with all allowances
	mapping (address => mapping (address => uint256)) internal allowed;

	//! Check the amount of tokens that an owner allowed to a spender
	function allowance(address owner, address spender) public constant returns (uint256 remaining) {
		return allowed[owner][spender];
	}

	/*!	Keep the list of addresses of holders up-to-dated
		It is important to have the list up-to-dated to have
		other contracts to communicate with or to do operations
		with all holders of tokens
	 */
	mapping (address => bool) public isHolder;
	address [] public holders;

	//! Sending coins by msg.sender to another address
	function transfer(address to, uint256 value) public returns (bool) {
		require(transfersAreAllowed);	// Transfers are allowed
		require(to != address(this));	// Prevent transfer to contract
		require(to != 0x0);				// Prevent transfer to 0x0 address.
		// SafeMath.sub/add checks and throw if there is not enough balance.
		balances[msg.sender] = balances[msg.sender].sub(value);
		balances[to] = balances[to].add(value);
		// Update the list of holders for new address
		if (isHolder[to] != true) {
			holders[holders.length++] = to;
			isHolder[to] = true;
		}
		// Notify anyone listening that this transfer took place
		Transfer(msg.sender, to, value);
		return true;
	}

	//! Approve the passed address to spend the specified amount of tokens on behalf of msg.sender
	function approve(address spender, uint256 value) public returns (bool) {
		allowed[msg.sender][spender] = value;
		// Notify anyone listening that this approval took place
		Approval(msg.sender, spender, value);
		return true;
	}

	//! Transfer tokens from one address to another with respect of allowances
	function transferFrom(address from, address to, uint256 value) public returns (bool) {
		require(transfersAreAllowed);	// Transfers are allowed
		require(to != address(this));	// Prevent transfer to contract
		require(to != address(0));		// Prevent transfer to 0x0 address.
		// SafeMath.sub/add checks and throw if there is not enough balance.
		balances[from] = balances[from].sub(value);
		balances[to] = balances[to].add(value);
		// Check the allowance
		uint256 allow = allowed[from][msg.sender];
		// sub() throws if value more than allowance
		allowed[from][msg.sender] = allow.sub(value);
		// Update the list of holders for new address
		if (isHolder[to] != true) {
			holders[holders.length++] = to;
			isHolder[to] = true;
		}
		// Notify anyone listening that this transfer took place
		Transfer(from, to, value);
		return true;
	}

	/*!	Contructor
	 */
	function SaavCoins() {
		name = "SAAV Coins";		// Set the name for display purposes
		symbol = "SAAV";			// Set the symbol for display purposes
		decimals = 0;				// Amount of decimals for display purposes
		decimalsMultiplier = 1;		// Multiplier for decimals

		totalSupply = 1000000000; 							// 1B SAAV
		totalSupply = totalSupply.mul(decimalsMultiplier);	// (decimals)
		balances[msg.sender] = totalSupply;					// All to owner
		holders[holders.length++] = msg.sender;
		isHolder[msg.sender] = true;
	}
}

/*!	Functionality to support migrations to new upgraded contract
	for SAAV coins. Only has effect if migrations are enabled and
	address of new contract is known.
 */
contract SaavCoinsMigratory is SaavCoins {
	using SafeMath for uint256;

	//! Address of new contract for possible upgrades
	address public migrationAgent;

	//! Counter to iterate (by portions) through all addresses for migration
	uint256 public migrationCountComplete;

	/*! Setup the address for new contract (to migrate coins to)
		Can be called only by owner (onlyOwner)
	 */
	function adminSetMigrationAgent(address agent) onlyOwner {
		migrationAgent = agent;
	}

	/*! Migrate tokens to the new token contract
		The method can be only called when migration agent is set.

		Can be called by user(holder) that would like to transfer
		coins to new contract immediately.
	 */
	function migrate() public returns (bool) {
		require(migrationAgent != 0x0);
		uint256 value = balances[msg.sender];
		balances[msg.sender] = balances[msg.sender].sub(value);
		totalSupply = totalSupply.sub(value);
		MigrationAgent(migrationAgent).migrateFrom(msg.sender, value);
		// Notify anyone listening that this migration took place
		Migrate(msg.sender, value);
		return true;
	}

	/*! Migrate holders of tokens to the new contract
		The method can be only called when migration agent is set.

		Can be called only by owner (onlyOwner)
	 */
	function adminMigrateHolders(uint256 count) onlyOwner public returns (bool) {
		require(count > 0);
		require(migrationAgent != 0x0);
		// Calculate bounds for processing
		count = migrationCountComplete + count;
		if (count > holders.length) {
			count = holders.length;
		}
		// Process migration
		for (uint256 i = migrationCountComplete; i < count; i++) {
			address holder = holders[i];
			uint value = balances[holder];
			balances[holder] = balances[holder].sub(value);
			totalSupply = totalSupply.sub(value);
			MigrationAgent(migrationAgent).migrateFrom(holder, value);
			// Notify anyone listening that this migration took place
			Migrate(holder, value);
		}
		migrationCountComplete = count;
		return true;
	}

	event Migrate(address indexed owner, uint256 value);

	/*!	Contructor
	 */
	function SaavCoinsMigratory() {
		migrationAgent = 0x0;
		migrationCountComplete = 0;
	}
}

contract SaavCoinsICO is SaavCoinsMigratory {
	using SafeMath for uint256;

	/*!	Define the amount allowed for sale only
		The difference with totalSupply is the reserved amount.
	 */
	uint256 public totalSupplyForSale;

	/*!	SAAV coins sale function.
		Works only if sale is allowed
		and totalSupplyForSale has enough coins.

		In case of migration logic activated, the holder just
		need to transfer smallest amount 1 Wei to activate the
		coins migration to new contract.
	 */
	function () payable {
		require(saleIsAllowed || migrationAgent != 0x0);
		// If sale is going
		if (saleIsAllowed) {
			// Calculate the amount by using ETH/USD rate
			uint256 value = msg.value;
			value = value.mul(usdForOneEth);
			value = value.mul(saavPerUsd);			// (SAAVs per USD)
			value = value.mul(decimalsMultiplier);	// (decimals)
			value = value.div(1 ether);
			// SafeMath.sub/add checks and throw if there is not enough supply.
			totalSupplyForSale = totalSupplyForSale.sub(value);
			// Border when bonus added
			uint256 bonused = minimumUsdValueForBonus;
			bonused = bonused.mul(saavPerUsd);			// (SAAVs per USD)
			bonused = bonused.mul(decimalsMultiplier);	// (decimals)
			// Bonus itself
			uint256 bonus = bonusInUsd;
			bonus = bonus.mul(saavPerUsd); 			// (SAAVs per USD)
			bonus = bonus.mul(decimalsMultiplier);	// (decimals)
			// Check bonus
			if (value >= bonused) {
				value = value.add(bonus); /* Bonus applied */
			}
			// SafeMath.sub/add checks and throw if there is not enough balance.
			balances[owner] = balances[owner].sub(value);
			balances[msg.sender] = balances[msg.sender].add(value);
			// Update the list of holders for new address
			if (isHolder[msg.sender] != true) {
				holders[holders.length++] = msg.sender;
				isHolder[msg.sender] = true;
			}
			// Notify anyone listening that this transfer took place
			Transfer(owner, msg.sender, value);
		} else if (migrationAgent != 0x0) {
			migrate();
		}
	}

	/*!	Admin function (onlyOwner) to transfer tokens in mode when:
			transfersAreAllowed is off

		Cases:
			a) Supporting users buying tokens for other currencies but provides
				Ether address later. The operations are next:
				1. tokens first reserved to special address (this call)
				2. later transfered to the user as Ether address is provided
			b) Operations with coins which are outside of ICO sale
				totalSupplyForSale is not changed in this transfer
				(when saleIsAllowed is off)

		Allow only transfer from owner account.
		This method can not transfer from users account.
	 */
	function adminTransferTo(address to, uint256 value) onlyOwner public returns (bool) {
		require(to != address(0));		// Prevent transfer to 0x0 address.
		// SafeMath.sub/add checks and throw if there is not enough balance.
		balances[owner] = balances[owner].sub(value);
		balances[to] = balances[to].add(value);
		// Update the list of holders for new address
		if (isHolder[to] != true) {
			holders[holders.length++] = to;
			isHolder[to] = true;
		}
		if (saleIsAllowed) {
			// SafeMath.sub/add checks and throw if there is not enough supply.
			totalSupplyForSale = totalSupplyForSale.sub(value);
		}
		// Notify anyone listening that this transfer took place
		Transfer(owner, to, value);
		return true;
	}

	/*!	Contructor
	 */
	function SaavCoinsICO() {
		totalSupplyForSale = 750000000; 	// 750M SAAV
		totalSupplyForSale = totalSupplyForSale.mul(decimalsMultiplier);

		uint256 b1 = 400000;
		b1 = b1.mul(decimalsMultiplier);
		adminTransferTo(0x359a4057FbF087A53b987E82e73391DB22151184, b1);

		uint256 b2 = 100000;
		b2 = b2.mul(decimalsMultiplier);
		adminTransferTo(0x444cf900Bbe99117F8158f9F8E19cec4bE5aF90D, b2);

	}
}
