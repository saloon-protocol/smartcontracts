// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./lib/ERC721Upgradeable.sol";
import "prb-math/UD60x18.sol";
import "./interfaces/ISaloon.sol";
import "./SaloonLib.sol";

//TODO Turn some magic numbers used in calculateEffectiveAPY to constants

/* 
BountyToken ERC721
================================================
    ** Default Variables **
================================================
Default Curve: 1/(0.66x+0.1) 
--------------------------------
defaultAPY "average" ~= 1.06
--------------------------------
default MaxAPY(y-value) = 10 
--------------------------------
default max x-value = 5
--------------------------------
max-to-standard APY ratio:
ratio = ~9.43 = maxAPY/defaultAPY 
e.g 10/1.06 ~= 9.43
--------------------------------
Definite Integral to calculate effective APY:
(50000000000000 * ((ln(33 * (sk)) + 5_000_000) - ln((33 * s) + 5_000_000))) / 33
--------------------------------
Notes:
Default Curve is used to calculate the staking reward.
Such reward is then multiplied by scalingMultiplier to match the targetAPY offered by the project,
which my differ from the standard 1.06%
================================================
================================================
*/

contract BountyTokenNFT is ISaloon, ERC721Upgradeable {
    //Constants
    uint256 constant DEFAULT_APY = 1.06 ether;
    uint256 constant BPS = 10_000;
    uint256 constant PRECISION = 1e18;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    mapping(uint256 => NFTInfo) public nftInfo; // tokenId => NFTInfo
    mapping(uint256 => uint256[]) public pidNFTList; // pid => tokenIds

    constructor() initializer {
        __ERC721_init("BountyToken", "BTT");
    }

    /// @notice Gets Current APY of pool (y-value) scaled to target APY
    /// @param _pid Bounty pool id
    function getCurrentAPY(uint256 _pid)
        public
        view
        returns (uint256 currentAPY)
    {
        PoolInfo memory pool = poolInfo[_pid];

        // get current x-value
        uint256 x = pool.curveInfo.currentX;
        // get pool multiplier
        uint256 m = pool.generalInfo.scalingMultiplier;

        // current unit APY = current y-value * scalingMultiplier
        currentAPY = SaloonLib.getCurrentAPY(x, m);
    }

    /// @notice Calculates effective APY staker will be entitled to in exchange for amount staked
    /// @dev formula for calculating effective price:
    ///      (50000000000000 * ((ln(33 * (sk)) + 5_000_000) - ln((33 * s) + 5_000_000))) / 33
    /// @param _pid Bounty pool id
    /// @param _stake amount to be staked
    /// @param _x Arbitrary X value
    function calculateEffectiveAPY(
        uint256 _pid,
        uint256 _stake,
        uint256 _x
    ) public view returns (uint256 scaledAPY) {
        PoolInfo memory pool = poolInfo[_pid];

        scaledAPY = SaloonLib.calculateArbitraryEffectiveAPY(
            _stake,
            _x,
            pool.generalInfo.poolCap,
            pool.generalInfo.scalingMultiplier
        );
    }

    /// @notice Update current pool size (X value)
    /// @dev reflects the new value of X in relation to change in pool size
    /// @param _pid Bounty pool id
    /// @param _newX New X value
    function _updateCurrentX(uint256 _pid, uint256 _newX)
        internal
        returns (bool)
    {
        poolInfo[_pid].curveInfo.currentX = _newX;
        return true;
    }

    ///  update unit APY value (y value)
    /// @param _x current x-value representing total stake amount
    /// @param _pid ID of pool
    function _updateCurrentY(uint256 _pid, uint256 _x)
        internal
        returns (uint256 newAPY)
    {
        newAPY = SaloonLib._curveImplementation(_x);
        poolInfo[_pid].curveInfo.currentY = newAPY;
    }

    function _removeNFTFromPidList(uint256 _tokenId) internal {
        NFTInfo memory token = nftInfo[_tokenId];
        uint256 pid = token.pid;

        uint256[] memory cachedList = pidNFTList[pid];
        uint256 length = cachedList.length;
        uint256 pos;

        for (uint256 i = 0; i < length; ++i) {
            if (cachedList[i] == _tokenId) {
                pos = i;
                break;
            }
        }

        if (pos >= length) revert("Token not found in array");

        for (uint256 i = pos; i < length - 1; ++i) {
            cachedList[i] = cachedList[i + 1];
        }
        pidNFTList[pid] = cachedList;
        pidNFTList[pid].pop(); // Can't pop from array in memory, so pop after writing to storage
    }

    /// @notice Mints ERC721 to staker representing their stake and how much APY they are entitled to
    /// @dev also updates pool variables
    /// @param _pid Bounty pool id
    /// @param _staker Staker address
    /// @param _stake Stake amount
    function _mint(
        uint256 _pid,
        address _staker,
        uint256 _stake
    ) internal returns (uint256) {
        require(_staker != address(0), "ERC20: mint to the zero address");

        uint256 apy = calculateEffectiveAPY(
            _pid,
            _stake,
            poolInfo[_pid].curveInfo.currentX
        );
        // uint256 apy = poolInfo[_pid].generalInfo.apy;

        uint256 tokenId = super._mint(_staker);

        NFTInfo memory token;

        token.pid = _pid;
        // Convert _amount to X value
        token.amount = _stake;
        (uint256 xDelta, ) = SaloonLib._convertStakeToPoolMeasurements(
            _stake,
            poolInfo[_pid].generalInfo.poolCap
        );

        require(
            poolInfo[_pid].curveInfo.totalSupply + xDelta <= 5 ether,
            "X boundary violated"
        );

        token.xDelta = xDelta;
        token.apy = apy;
        token.lastClaimedTime = block.timestamp;
        nftInfo[tokenId] = token;

        pidNFTList[_pid].push(tokenId);

        poolInfo[_pid].curveInfo.totalSupply += xDelta;
        _updateCurrentX(_pid, poolInfo[_pid].curveInfo.totalSupply);

        // _afterTokenTransfer(address(0), _staker, _amount);

        return tokenId;
    }

    /// @notice Processes unstakes and calculates new APY for remaining stakers of a specific pool
    /// @param _pid Bounty pool id
    function consolidate(uint256 _pid) public {
        PoolInfo memory pool = poolInfo[_pid];
        uint256[] memory unstakedTokens = pool.curveInfo.unstakedTokens;
        uint256 unstakeLength = unstakedTokens.length;

        if (unstakeLength == 0 || !pool.isActive) return; // No unstakes have occured, no need to consolidate

        for (uint256 i = 0; i < unstakeLength; ++i) {
            _removeNFTFromPidList(unstakedTokens[i]);
        }

        uint256[] memory tokenArray = pidNFTList[_pid];
        uint256 length = tokenArray.length;
        uint256 memX;

        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenArray[i];
            NFTInfo storage token = nftInfo[tokenId];
            uint256 stakeAmount = token.amount;
            token.apy = calculateEffectiveAPY(_pid, stakeAmount, memX);
            memX += token.xDelta;
        }

        poolInfo[_pid].curveInfo.totalSupply = memX;
        delete poolInfo[_pid].curveInfo.unstakedTokens;
    }

    /// @notice Processes unstakes and calculates new APY for remaining stakers for all pools
    function consolidateAll() external {
        uint256 arrayLength = poolInfo.length;
        for (uint256 i = 0; i < arrayLength; ++i) {
            consolidate(i);
        }
    }

    function receiveStrategyYield(address _token, uint256 _amount)
        external
        virtual
    {}

    function getAllTokensByOwner(address _owner)
        public
        view
        returns (NFTInfo[] memory userTokens)
    {
        uint256[] memory tokens = _ownedTokens[_owner];
        uint256 tokenLength = tokens.length;
        userTokens = new NFTInfo[](tokenLength);

        for (uint256 i = 0; i < tokenLength; ++i) {
            userTokens[i] = nftInfo[tokens[i]];
        }
    }
}
