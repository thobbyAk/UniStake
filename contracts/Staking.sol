//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./BearToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/UniswapV2ERC20.sol";

contract Staking is Ownable {
    using SafeERC20 for UniswapV2ERC20; // Wrappers around ERC20 operations that throw on failure
    BearToken public bearToken;
    uint256 private rewardTokensPerBlock; // Number of reward tokens minted per block
    uint256 private constant REWARDS_PRECISION = 1e12; // A big number to perform mul and div operations

    struct PoolStaker {
        uint256 amount; // The tokens quantity the user has staked.
        uint256 rewards; // The reward tokens quantity the user can harvest
        uint256 rewardDebt; // The amount relative to accumulatedRewardsPerShare the user can't get as reward
    }

    // Staking pool
    struct Pool {
        UniswapV2ERC20 stakeToken; // Token to be staked
        uint256 tokensStaked; // Total tokens staked
        uint256 lastRewardedBlock; // Last block number the user had their rewards calculated
        uint256 accumulatedRewardsPerShare; // Accumulated rewards per share times REWARDS_PRECISION
    }

    Pool[] public pools; // Staking pools

    // Mapping poolId => staker address => PoolStaker
    mapping(uint256 => mapping(address => PoolStaker)) public poolStakers;

    // Events
    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdraw(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );
    event HarvestRewards(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );
    event PoolCreated(uint256 poolId);

    // Constructor
    constructor(address _rewardTokenAddress, uint256 _rewardTokensPerBlock) {
        bearToken = BearToken(_rewardTokenAddress);
        rewardTokensPerBlock = _rewardTokensPerBlock;
    }

    /**
     * @dev Create a new staking pool
     */

    function createPool(UniswapV2ERC20 _stakeToken) external onlyOwner {
        Pool memory pool;
        pool.stakeToken = _stakeToken;
        pools.push(pool);
        uint256 poolId = pools.length - 1;
        emit PoolCreated(poolId);
    }

    function poolLength() external view returns (uint256) {
        return pools.length;
    }

    function deposit(uint256 _poolId, uint256 _amount) external {
        require(_amount > 0, "Deposit amount can't be zero");
        Pool storage pool = pools[_poolId];
        PoolStaker storage staker = poolStakers[_poolId][msg.sender];

        // Update pool stakers
        harvestRewards(_poolId);

        // Update current staker
        staker.amount = staker.amount + _amount;
        staker.rewardDebt =
            (staker.amount * pool.accumulatedRewardsPerShare) /
            REWARDS_PRECISION;

        // Update pool
        pool.tokensStaked = pool.tokensStaked + _amount;

        // Deposit tokens
        emit Deposit(msg.sender, _poolId, _amount);
        pool.stakeToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
    }

    /**
     * @dev Withdraw all tokens from an existing pool
     */
    function withdraw(uint256 _poolId) external {
        Pool storage pool = pools[_poolId];
        PoolStaker storage staker = poolStakers[_poolId][msg.sender];
        uint256 amount = staker.amount;
        require(amount > 0, "Withdraw amount can't be zero");

        // Pay rewards
        harvestRewards(_poolId);

        // Update staker
        staker.amount = 0;
        staker.rewardDebt =
            (staker.amount * pool.accumulatedRewardsPerShare) /
            REWARDS_PRECISION;

        // Update pool
        pool.tokensStaked = pool.tokensStaked - amount;

        // Withdraw tokens
        emit Withdraw(msg.sender, _poolId, amount);
        pool.stakeToken.safeTransfer(address(msg.sender), amount);
    }

    /**
     * @dev allows staking reward token into the contract
     */

    function enterStaking(uint256 _amount) public {
        Pool storage pool = pools[0];
        PoolStaker storage staker = poolStakers[0][msg.sender];
        updatePoolRewards(0);
        if (staker.amount > 0) {
            uint256 pending = ((staker.amount *
                pool.accumulatedRewardsPerShare) / REWARDS_PRECISION) -
                staker.rewardDebt;
            if (pending > 0) {
                bearToken.transfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.stakeToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            staker.amount = staker.amount + _amount;
        }

        staker.rewardDebt =
            (staker.amount * pool.accumulatedRewardsPerShare) /
            REWARDS_PRECISION;
        bearToken.mint(msg.sender, _amount);

        emit Deposit(msg.sender, 0, _amount);
    }

    /**
     * @dev allows users to unstake reward token into the contract
     */
    function leaveStaking(uint256 _amount) public {
        Pool storage pool = pools[0];
        PoolStaker storage staker = poolStakers[0][msg.sender];
        updatePoolRewards(0);
        require(staker.amount >= _amount, "withdraw: not good");
        uint256 pending = ((staker.amount * pool.accumulatedRewardsPerShare) /
            REWARDS_PRECISION) - staker.rewardDebt;
        if (pending > 0) {
            bearToken.transfer(msg.sender, pending);
        }
        if (_amount > 0) {
            staker.amount = staker.amount - _amount;
            pool.stakeToken.safeTransfer(address(msg.sender), _amount);
        }

        staker.rewardDebt =
            (staker.amount * pool.accumulatedRewardsPerShare) /
            REWARDS_PRECISION;

        bearToken.burn(msg.sender, _amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    /**
     * @dev Harvest user rewards from a given pool id
     */
    function harvestRewards(uint256 _poolId) public {
        updatePoolRewards(_poolId);
        Pool storage pool = pools[_poolId];
        PoolStaker storage staker = poolStakers[_poolId][msg.sender];
        uint256 rewardsToHarvest = ((staker.amount *
            pool.accumulatedRewardsPerShare) / REWARDS_PRECISION) -
            staker.rewardDebt;
        if (rewardsToHarvest == 0) {
            staker.rewardDebt =
                (staker.amount * pool.accumulatedRewardsPerShare) /
                REWARDS_PRECISION;
            return;
        }
        staker.rewards = 0;
        staker.rewardDebt =
            (staker.amount * pool.accumulatedRewardsPerShare) /
            REWARDS_PRECISION;
        emit HarvestRewards(msg.sender, _poolId, rewardsToHarvest);
        bearToken.mint(msg.sender, rewardsToHarvest);
    }

    /**
     * @dev Update pool's accumulatedRewardsPerShare and lastRewardedBlock
     */
    function updatePoolRewards(uint256 _poolId) private {
        Pool storage pool = pools[_poolId];
        if (pool.tokensStaked == 0) {
            pool.lastRewardedBlock = block.number;
            return;
        }
        uint256 blocksSinceLastReward = block.number - pool.lastRewardedBlock;
        uint256 rewards = blocksSinceLastReward * rewardTokensPerBlock;
        pool.accumulatedRewardsPerShare =
            pool.accumulatedRewardsPerShare +
            ((rewards * REWARDS_PRECISION) / pool.tokensStaked);
        pool.lastRewardedBlock = block.number;
    }
}
