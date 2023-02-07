// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./lib/ERC721Upgradeable.sol";
import "prb-math/UD60x18.sol";
import "./interfaces/ISaloon.sol";

//TODO Turn some magic numbers used in calculateEffectiveAPY to constants

/* 
BountyToken ERC20
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
Definite Integral:
(50000000000000 * ((ln(33 * (sk)) + 5_000_000) - ln((33 * s) + 5_000_000))) / 33
--------------------------------
Notes:
Default Curve is used to calculate the staking reward.
Such reward is then multiplied by multiplier to match the targetAPY offered by the project,
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

    // staker address => poolID => staker balance
    mapping(uint256 => uint256) public nftBalance;

    mapping(uint256 => uint256) public nftAPY;

    struct NFTInfo {
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

    /// @notice Calculates multiplier given targetAPY
    /// @param _targetAPY the advertised average APY of a bounty
    /// @param _pid poolID that the multiplier will be assigned to
    function updateMultiplier(uint256 _pid, uint256 _targetAPY) internal {
        uint256 m = (_targetAPY * PRECISION) / DEFAULT_APY;
        poolInfo[_pid].generalInfo.multiplier = m;
    }

    // Default curve function implementation
    //      1/(0.66x+0.1)
    function curveImplementation(uint256 _x) internal pure returns (uint256 y) {
        uint256 denominator = ((0.66 ether * _x) / 1e18) + 0.1 ether;
        y = (1 ether * 1e18) / denominator;
    }

    //  Get Current APY of pool (y-value) scaled to target APY
    function getCurrentAPY(uint256 _pid)
        public
        view
        returns (uint256 currentAPY)
    {
        PoolInfo memory pool = poolInfo[_pid];

        // get current x-value
        uint256 x = pool.tokenInfo.currentX;
        // current unit APY =  y-value * multiplier
        currentAPY = curveImplementation(x) * pool.generalInfo.multiplier;
    }

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

    /// @notice calculates effective APY staker will be entitled to in exchange for amount staked
    /// @dev formula for calculating effective price:
    /// (50000000000000 * ((ln(33 * (sk)) + 5_000_000) - ln((33 * s) + 5_000_000))) / 33
    /// @param _stake amount to be staked
    /// @param _pid ID of current pool
    function calculateEffectiveAPY(uint256 _pid, uint256 _stake)
        public
        view
        returns (uint256 scaledAPY)
    {
        PoolInfo memory pool = poolInfo[_pid];
        // get current x
        uint256 s = pool.tokenInfo.currentX;
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

        // get pool Multiplier
        uint256 m = pool.generalInfo.multiplier;

        // calculate effective APY according to APY offered
        scaledAPY = (effectiveAPY * m) / PRECISION;
    }

    function calculateEffectiveAPYConsolidate(
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

        // get pool Multiplier
        uint256 m = pool.generalInfo.multiplier;

        // calculate effective APY according to APY offered
        scaledAPY = (effectiveAPY * m) / PRECISION;
    }

    // TODO * Register when a token is transferred between accounts so seller
    //   gets the rewards he is entitled to even after sale.
    //  /note - this might be a function for Saloon.sol?
    //

    // * update current pool size (x value)
    function updateCurrentX(uint256 _pid, uint256 _newX)
        internal
        returns (bool)
    {
        poolInfo[_pid].tokenInfo.currentX = _newX;
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
        poolInfo[_pid].tokenInfo.currentY = newAPY;
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

    // * mint function that includes pool ID when minting
    function _mint(
        uint256 _pid,
        address _staker,
        uint256 _amount
    ) internal returns (uint256) {
        require(_staker != address(0), "ERC20: mint to the zero address");

        uint256 apy = calculateEffectiveAPY(_pid, _amount);
        // uint256 apy = poolInfo[_pid].generalInfo.apy;

        uint256 tokenId = super._mint(_staker);

        NFTInfo memory token;

        // Convert _amount to _xAmount
        token.amount = _amount;
        (uint256 xDelta, ) = convertStakeToPoolMeasurements(_pid, _amount);

        require(
            poolInfo[_pid].tokenInfo.totalSupply + xDelta <= 5 ether,
            "X boundary violated"
        );

        token.xDelta = xDelta;
        token.apy = apy;
        token.lastClaimedTime = block.timestamp;
        nftInfo[tokenId] = token;

        pidNFTList[_pid].push(tokenId);
        nftToPid[tokenId] = _pid;

        poolInfo[_pid].tokenInfo.totalSupply += xDelta;
        updateCurrentX(_pid, poolInfo[_pid].tokenInfo.totalSupply);

        // _afterTokenTransfer(address(0), _staker, _amount);

        return tokenId;
    }

    //  balanceOf function  that checks for pool ID
    // function balanceOf(address _staker, uint256 _pid)
    //     public
    //     view
    //     returns (uint256)
    // {
    //     return stakerBalance[_staker][_pid];
    // }

    // function balanceOfPid(address _staker, uint256 _pid)
    //     public
    //     view
    //     returns (uint256)
    // {
    //     return stakerBalance[_staker][_pid];
    // }

    // burn function that takes into account poolID
    function _burn(uint256 _tokenId) internal override {
        uint256 pid = nftToPid[_tokenId];
        NFTInfo memory token = nftInfo[_tokenId];

        // _beforeTokenTransfer(_staker, address(0), _amount);

        super._burn(_tokenId);

        // emit Transfer(_staker, address(0), _amount);

        // _afterTokenTransfer(_staker, address(0), _amount);
    }

    function consolidate(uint256 _pid) public {
        PoolInfo memory pool = poolInfo[_pid];
        uint256[] memory unstakedTokens = pool.tokenInfo.unstakedTokens;
        uint256 unstakeLength = unstakedTokens.length;

        // NEED TO CHECK IF POOL IS ACTIVE/WOUND DOWN?? Any malicious project actions due to check?
        if (unstakeLength == 0 || !pool.isActive) return; // No unstakes have occured, no need to consolidate

        for (uint256 i = 0; i < unstakeLength; ++i) {
            removeNFTFromPidList(unstakedTokens[i]);
        }

        uint256[] memory tokenArray = pidNFTList[_pid];
        uint256 length = tokenArray.length;
        uint256 memX;
        // updateCurrentX(_pid, 0);

        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenArray[i];
            NFTInfo storage token = nftInfo[tokenId];
            uint256 stakeAmount = token.amount;
            token.apy = calculateEffectiveAPYConsolidate(
                _pid,
                stakeAmount,
                memX
            );
            memX += token.xDelta;
            // updateCurrentX(
            //     _pid,
            //     poolInfo[_pid].tokenInfo.totalSupply + stakeAmount
            // );
        }

        poolInfo[_pid].tokenInfo.totalSupply = memX;
    }

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
}
