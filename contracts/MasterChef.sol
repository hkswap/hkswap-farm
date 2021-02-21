// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import './libs/IBEP20.sol';
import './libs/SafeBEP20.sol';
import './libs/ITokenConverter.sol';
import "./HKSToken.sol";

// import "@nomiclabs/buidler/console.sol";

// MasterChef is the master of Cake. He can make Cake and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once HKS is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 sowBlock;   // user start to sow at this block - used for harvest
        uint256 pendingReward; // Reward pending. Used if you add liquidity to a locked reward pool
        //
        // We do some fancy math here. Basically, any point in time, the amount of HKSs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accCakePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accCakePerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. HKSs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that HKSs distribution occurs.
        uint256 accHKSPerShare; // Accumulated HKSs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
        uint256 growingDuration; // number of block to wait before harvest
    }

    // The HKS TOKEN!
    HKSToken public hks;
    // Dev address.
    address public devaddr;
    // HKS tokens created per block.
    uint256 public hksPerBlock;
    // feeAddress
    address public feeAddress;
    // Define a token converter
    ITokenConverter lpTokenConverter;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when HKS mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        HKSToken _hks,
        address _devaddr,
        address _feeAddress,
        uint256 _hksPerBlock,
        uint256 _startBlock
    ) public {
        hks = _hks;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        hksPerBlock = _hksPerBlock;
        startBlock = _startBlock;
        lpTokenConverter = ITokenConverter(address(0));
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate, uint16 _depositFeeBP, uint256 _growingDuration) public onlyOwner {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accHKSPerShare: 0,
        depositFeeBP: _depositFeeBP,
        growingDuration: _growingDuration
        }));
    }

    // Update the given pool's HKS allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate, uint16 _depositFeeBP, uint256 _growingDuration) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].growingDuration = _growingDuration;
    }

    // View function to see pending HKSs on frontend.
    function pendingHKS(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accHKSPerShare = pool.accHKSPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = block.number.sub(pool.lastRewardBlock);
            uint256 hksReward = multiplier.mul(hksPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accHKSPerShare = accHKSPerShare.add(hksReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accHKSPerShare).div(1e12).sub(user.rewardDebt).add(user.pendingReward);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number.sub(pool.lastRewardBlock);
        uint256 hksReward = multiplier.mul(hksPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        hks.mint(devaddr, hksReward.div(10));
        hks.mint(address(this), hksReward);
        pool.accHKSPerShare = pool.accHKSPerShare.add(hksReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // not especially dangerous - contract can be check before to do a convertible deposit
    function setTokenConverter(address _srcLpToken, address _destLpToken, address _lpConverter ) public onlyOwner {
        require( _srcLpToken != _destLpToken, 'HKS: Token are the same');
        lpTokenConverter = ITokenConverter(_lpConverter);
    }

    // Deposit LP tokens to MasterChef for HKS allocation from different token.
    function depositConvertibleLPToken(uint256 _pid, address _srcLpToken, uint256 _srcLpTokenAmount) public {
        require( lpTokenConverter != ITokenConverter(address(0)), 'HKS: Converter is currently unavailable');
        PoolInfo storage pool = poolInfo[_pid];

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 lpTokenAmountResult = lpTokenConverter.convertAndRePaid( _srcLpToken, _srcLpTokenAmount, address(pool.lpToken), msg.sender);
        // double check to avoid to be theft by the converter
        require( lpSupply.add(lpTokenAmountResult) == pool.lpToken.balanceOf(address(this)), 'HKS: Fund are missing or too much');

        deposit(_pid, lpTokenAmountResult);
    }

    // Deposit LP tokens to MasterChef for HKS allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accHKSPerShare).div(1e12).sub(user.rewardDebt).add(user.pendingReward);
            if(pending > 0) {
                if ( block.number.sub(user.sowBlock) < poolInfo[_pid].growingDuration){
                    user.pendingReward = pending;
                } else {
                    user.pendingReward = 0;
                    safeHKSTransfer(msg.sender, pending);
                }
            }
        } else {
            user.pendingReward = 0;
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if(pool.depositFeeBP > 0){
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            }else{
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accHKSPerShare).div(1e12);
        user.sowBlock = block.number;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        require ( block.number.sub(user.sowBlock) >= poolInfo[_pid].growingDuration, 'not harvest period yet - use emergency withdraw');

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accHKSPerShare).div(1e12).sub(user.rewardDebt).add(user.pendingReward);
        if(pending > 0) {
            user.pendingReward = 0;
            safeHKSTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accHKSPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.pendingReward = 0;
    }

    // Safe hks transfer function, just in case if rounding error causes pool to not have enough HKSs.
    function safeHKSTransfer(address _to, uint256 _amount) internal {
        uint256 hksBal = hks.balanceOf(address(this));
        if (_amount > hksBal) {
            hks.transfer(_to, hksBal);
        } else {
            hks.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "feeAddress: wut?");
        feeAddress = _feeAddress;
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _hksPerBlock) public onlyOwner {
        massUpdatePools();
        hksPerBlock = _hksPerBlock;
    }
}
