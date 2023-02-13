// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./lib/ERC721Upgradeable.sol";
import "prb-math/UD60x18.sol";
import "./interfaces/ISaloon.sol";

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

    struct NFTInfo {
        uint256 pid;
        uint256 amount;
        uint256 xDelta;
        uint256 apy;
        uint256 unclaimed;
        uint256 lastClaimedTime;
        uint256 timelock;
        uint256 timelimit;
    }

    mapping(uint256 => uint256) public nftToPid;
    mapping(uint256 => NFTInfo) public nftInfo; // tokenId => NFTInfo
    mapping(uint256 => uint256[]) public pidNFTList; // pid => tokenIds

    constructor() initializer {
        __ERC721_init("BountyToken", "BTT");
    }

    /// @notice Calculates scalingMultiplier given targetAPY
    /// @param _targetAPY the advertised average APY of a bounty
    /// @param _pid poolID that the scalingMultiplier will be assigned to
    function updateScalingMultiplier(uint256 _pid, uint256 _targetAPY)
        internal
    {
        uint256 sm = (_targetAPY * PRECISION) / DEFAULT_APY;
        poolInfo[_pid].generalInfo.scalingMultiplier = sm;
    }

    /// @notice Default curve function implementation
    /// @dev calculates Y given X
    ///     -    1/(0.66x+0.1)
    ///     - Y = APY
    ///     - X = total token amount in pool scaled to X variable
    /// @param _x X value
    function curveImplementation(uint256 _x) internal pure returns (uint256 y) {
        uint256 denominator = ((0.66 ether * _x) / 1e18) + 0.1 ether;
        y = (1 ether * 1e18) / denominator;
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
        // current unit APY =  y-value * scalingMultiplier
        currentAPY =
            curveImplementation(x) *
            pool.generalInfo.scalingMultiplier;
    }

    /// @notice Convert token amount to X value equivalent
    /// @dev max X value is 5
    /// @param _pid Bounty pool id
    /// @param _stake Amount to be converted
    function convertStakeToPoolMeasurements(uint256 _pid, uint256 _stake)
        internal
        view
        returns (uint256 x, uint256 poolPercentage)
    {
        poolPercentage =
            (_stake * PRECISION) /
            poolInfo[_pid].generalInfo.poolCap;

        x = 5 * poolPercentage;
    }

    /// @notice Calculates effective APY staker will be entitled to in exchange for amount staked
    /// @dev formula for calculating effective price:
    ///      (50000000000000 * ((ln(33 * (sk)) + 5_000_000) - ln((33 * s) + 5_000_000))) / 33
    /// @param _pid Bounty pool id
    /// @param _stake amount to be staked
    function calculateEffectiveAPY(uint256 _pid, uint256 _stake)
        public
        view
        returns (uint256 scaledAPY)
    {
        PoolInfo memory pool = poolInfo[_pid];
        // get current x
        uint256 s = pool.curveInfo.currentX;
        // convert stake to x-value
        (uint256 k, ) = convertStakeToPoolMeasurements(_pid, _stake);
        uint256 sk = k + s;

        uint256 l1 = ((33 * (sk)) + 5 ether);
        uint256 l2 = ((33 * s) + 5 ether);

        // lns
        UD60x18 ln1 = ln(toUD60x18(l1));
        UD60x18 ln2 = ln(toUD60x18(l2));
        UD60x18 res = toUD60x18(50_000_000 ether).mul(ln1.sub(ln2)).div(
            toUD60x18(33)
        );
        // calculate effective APY
        uint256 effectiveAPY = unwrap(res) / (k * 1e6);

        // get pool scalingMultiplier
        uint256 m = pool.generalInfo.scalingMultiplier;

        // calculate effective APY according to APY offered
        scaledAPY = (effectiveAPY * m) / PRECISION;
    }

    /// @notice Calculates effective APY for arbitrary values
    /// @param _pid Bounty pool id
    /// @param _stake Arbitrary stake amount
    /// @param _memX Arbitrary X value
    function calculateArbitraryEffectiveAPY(
        uint256 _pid,
        uint256 _stake,
        uint256 _memX
    ) public view returns (uint256 scaledAPY) {
        PoolInfo memory pool = poolInfo[_pid];
        // get current x
        uint256 s = _memX;
        // convert stake to x-value
        (uint256 k, ) = convertStakeToPoolMeasurements(_pid, _stake);
        uint256 sk = k + s;

        uint256 l1 = ((33 * (sk)) + 5 ether);
        uint256 l2 = ((33 * s) + 5 ether);

        // lns
        UD60x18 ln1 = ln(toUD60x18(l1));
        UD60x18 ln2 = ln(toUD60x18(l2));
        UD60x18 res = toUD60x18(50_000_000 ether).mul(ln1.sub(ln2)).div(
            toUD60x18(33)
        );
        // calculate effective APY
        uint256 effectiveAPY = unwrap(res) / (k * 1e6);

        // get pool scalingMultiplier
        uint256 sm = pool.generalInfo.scalingMultiplier;

        // calculate effective APY according to APY offered
        scaledAPY = (effectiveAPY * sm) / PRECISION;
    }

    // TODO * Register when a token is transferred between accounts so seller
    //   gets the rewards he is entitled to even after sale.
    //  /note - this might be a function for Saloon.sol?
    //

    /// @notice Update current pool size (X value)
    /// @dev reflects the new value of X in relation to change in pool size
    /// @param _pid Bounty pool id
    /// @param _newX New X value
    function updateCurrentX(uint256 _pid, uint256 _newX)
        internal
        returns (bool)
    {
        poolInfo[_pid].curveInfo.currentX = _newX;
        return true;
    }

    ///  update unit APY value (y value)
    /// @param _x current x-value representing total stake amount
    /// @param _pid ID of pool
    function updateCurrentY(uint256 _pid, uint256 _x)
        internal
        returns (uint256 newAPY)
    {
        newAPY = curveImplementation(_x);
        poolInfo[_pid].curveInfo.currentY = newAPY;
    }

    function removeNFTFromPidList(uint256 _tokenId) internal {
        uint256 pid = nftToPid[_tokenId];

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

        uint256 apy = calculateEffectiveAPY(_pid, _stake);
        // uint256 apy = poolInfo[_pid].generalInfo.apy;

        uint256 tokenId = super._mint(_staker);

        NFTInfo memory token;

        token.pid = _pid;
        // Convert _amount to X value
        token.amount = _stake;
        (uint256 xDelta, ) = convertStakeToPoolMeasurements(_pid, _stake);

        require(
            poolInfo[_pid].curveInfo.totalSupply + xDelta <= 5 ether,
            "X boundary violated"
        );

        token.xDelta = xDelta;
        token.apy = apy;
        token.lastClaimedTime = block.timestamp;
        nftInfo[tokenId] = token;

        pidNFTList[_pid].push(tokenId);
        nftToPid[tokenId] = _pid;

        poolInfo[_pid].curveInfo.totalSupply += xDelta;
        updateCurrentX(_pid, poolInfo[_pid].curveInfo.totalSupply);

        // _afterTokenTransfer(address(0), _staker, _amount);

        return tokenId;
    }

    // /// @notice Burns token Id
    // /// @param _tokenId ERC721 token id to be burned
    // function _burn(uint256 _tokenId) internal override {
    //     // uint256 pid = nftToPid[_tokenId];
    //     // NFTInfo memory token = nftInfo[_tokenId];

    //     super._burn(_tokenId);

    //     // emit Transfer(_staker, address(0), _amount); //todo delete this?

    //     // _afterTokenTransfer(_staker, address(0), _amount); //todo delete this?
    // }

    /// @notice Processes unstakes and calculates new APY for remaining stakers of a specific pool
    /// @param _pid Bounty pool id
    function consolidate(uint256 _pid) public {
        PoolInfo memory pool = poolInfo[_pid];
        uint256[] memory unstakedTokens = pool.curveInfo.unstakedTokens;
        uint256 unstakeLength = unstakedTokens.length;

        //todo NEED TO CHECK IF POOL IS ACTIVE/WOUND DOWN?? Any malicious project actions due to check?
        if (unstakeLength == 0 || !pool.isActive) return; // No unstakes have occured, no need to consolidate

        for (uint256 i = 0; i < unstakeLength; ++i) {
            removeNFTFromPidList(unstakedTokens[i]);
        }

        uint256[] memory tokenArray = pidNFTList[_pid];
        uint256 length = tokenArray.length;
        uint256 memX;
        // updateCurrentX(_pid, 0); //todo delete this?

        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenArray[i];
            NFTInfo storage token = nftInfo[tokenId];
            uint256 stakeAmount = token.amount;
            token.apy = calculateArbitraryEffectiveAPY(_pid, stakeAmount, memX);
            memX += token.xDelta;
            // updateCurrentX( //todo delete this?
            //     _pid,
            //     poolInfo[_pid].curveInfo.totalSupply + stakeAmount
            // );
        }

        poolInfo[_pid].curveInfo.totalSupply = memX;
        // poolInfo[_pid].curveInfo.unstakedTokens = uint256[];
    }

    /// @notice Processes unstakes and calculates new APY for remaining stakers for all pools
    function consolidateAll() public {
        uint256 arrayLength = poolInfo.length;
        for (uint256 i = 0; i < arrayLength; ++i) {
            consolidate(i);
        }
    }

    function receiveStrategyYield(address _token, uint256 _amount)
        external
        virtual
    {}

    function getAllTokensByOwner(address owner)
        public
        view
        returns (NFTInfo[] memory userTokens)
    {
        uint256[] memory tokens = _ownedTokens[owner];
        uint256 tokenLength = tokens.length;
        uint256 index = 0;
        for (uint256 i = 0; i < tokenLength; ++i) {
            userTokens[index] = nftInfo[tokens[i]];
            index++;
        }
    }
}
