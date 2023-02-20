// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./lib/ERC721Upgradeable.sol";
import "prb-math/UD60x18.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
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

contract BountyTokenNFT is ERC721Upgradeable {
    using SafeMath for uint256;

    //Constants
    uint256 constant DEFAULT_APY = 1.06 ether;
    uint256 constant PRECISION = 1e18;
    uint256 constant saloonFee = 1000; // 10%
    uint256 constant BPS = 10_000;
    uint256 constant YEAR = 365 days;
    uint256 constant PERIOD = 1 weeks;

    address public owner;
    ISaloon saloon;

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

    mapping(uint256 => NFTInfo) public nftInfo; // tokenId => NFTInfo
    mapping(uint256 => uint256[]) public pidNFTList; // pid => tokenIds

    modifier onlyOwner() {
        require(msg.sender == owner, "SBT: not authorized");
        _;
    }

    constructor(address _owner) initializer {
        require(_owner != address(0));
        __ERC721_init("SaloonBountyToken", "SBT");
        owner = _owner;
        saloon = ISaloon(_owner);
    }

    /// @notice Calculates scalingMultiplier given targetAPY
    /// @param _targetAPY the advertised average APY of a bounty
    function calculateScalingMultiplier(uint256 _targetAPY)
        external
        returns (uint256 sm)
    {
        sm = (_targetAPY * PRECISION) / DEFAULT_APY;
    }

    /// @notice Default curve function implementation
    /// @dev calculates Y given X
    ///     -    1/(0.66x+0.1)
    ///     - Y = APY
    ///     - X = total token amount in pool scaled to X variable
    /// @param _x X value
    function curveImplementation(uint256 _x) external pure returns (uint256 y) {
        uint256 denominator = ((0.66 ether * _x) / 1e18) + 0.1 ether;
        y = (1 ether * 1e18) / denominator;
    }

    /// @notice Convert token amount to X value equivalent
    /// @dev max X value is 5
    /// @param _pid Bounty pool id
    /// @param _stake Amount to be converted
    function _convertStakeToPoolMeasurements(uint256 _pid, uint256 _stake)
        internal
        view
        returns (uint256 x, uint256 poolPercentage)
    {
        poolPercentage =
            (_stake * PRECISION) /
            saloon.getPoolInfo(_pid).generalInfo.poolCap;

        x = 5 * poolPercentage;
    }

    /// @notice Calculates effective APY staker will be entitled to in exchange for amount staked
    /// @dev formula for calculating effective price:
    ///      (50000000000000 * ((ln(33 * (sk)) + 5_000_000) - ln((33 * s) + 5_000_000))) / 33
    /// @param _pid Bounty pool id
    /// @param _stake amount to be staked
    function calculateEffectiveAPY(
        uint256 _pid,
        uint256 _stake,
        bool _simulation,
        uint256 _memX
    ) public view returns (uint256 scaledAPY) {
        ISaloon.PoolInfo memory pool = saloon.getPoolInfo(_pid);
        // get current x
        uint256 s;
        if (_simulation) {
            s = _memX;
        } else {
            s = pool.curveInfo.currentX;
        }

        // convert stake to x-value
        (uint256 k, ) = _convertStakeToPoolMeasurements(_pid, _stake);
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

    function mint(
        uint256 _pid,
        address _staker,
        uint256 _stake
    ) external onlyOwner returns (uint256 tokenId) {
        tokenId = _mint(_pid, _staker, _stake);
    }

    function burn(uint256 _tokenId) external onlyOwner {
        _burn(_tokenId);
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

        uint256 apy = calculateEffectiveAPY(_pid, _stake, false, 0);
        // uint256 apy = getPoolInfo[_pid].generalInfo.apy;

        uint256 tokenId = super._mint(_staker);

        NFTInfo memory token;

        token.pid = _pid;
        // Convert _amount to X value
        token.amount = _stake;
        (uint256 xDelta, ) = _convertStakeToPoolMeasurements(_pid, _stake);

        require(
            saloon.getPoolInfo(_pid).curveInfo.totalSupply + xDelta <= 5 ether,
            "X boundary violated"
        );

        token.xDelta = xDelta;
        token.apy = apy;
        token.lastClaimedTime = block.timestamp;
        nftInfo[tokenId] = token;

        pidNFTList[_pid].push(tokenId);

        saloon.increaseTotalSupply(_pid, xDelta);
        saloon.updateCurrentX(
            _pid,
            saloon.getPoolInfo(_pid).curveInfo.totalSupply
        );

        // _afterTokenTransfer(address(0), _staker, _amount);

        return tokenId;
    }

    /// @notice Processes unstakes and calculates new APY for remaining stakers of a specific pool
    /// @param _pid Bounty pool id
    function consolidate(uint256 _pid) public {
        uint256[] memory unstakedTokens = saloon
            .getPoolInfo(_pid)
            .curveInfo
            .unstakedTokens;
        uint256 unstakeLength = unstakedTokens.length;

        if (unstakeLength == 0 || !saloon.getPoolInfo(_pid).isActive) return; // No unstakes have occured, no need to consolidate

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
            token.apy = calculateEffectiveAPY(_pid, stakeAmount, true, memX);
            memX += token.xDelta;
        }

        saloon.finalizeConsolidation(_pid, memX);
    }

    /// @notice Processes unstakes and calculates new APY for remaining stakers for all pools
    function consolidateAll() external {
        uint256 arrayLength = saloon.poolLength();
        for (uint256 i = 0; i < arrayLength; ++i) {
            consolidate(i);
        }
    }

    function updateToken(uint256 _tokenId, NFTInfo memory _tokenData)
        external
        onlyOwner
    {
        nftInfo[_tokenId] = _tokenData;
    }

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

    /// @notice Calculates time passed in seconds from lastClaimedTime to endTime.
    /// @param _from lastClaimedTime
    /// @param _to endTime
    function _getSecondsPassed(uint256 _from, uint256 _to)
        private
        pure
        returns (uint256)
    {
        return _to.sub(_from);
    }

    function pendingPremium(uint256 _tokenId)
        public
        view
        returns (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        )
    {
        NFTInfo memory token = nftInfo[_tokenId];
        uint256 pid = token.pid;
        uint256 poolFreezeTime = saloon.getPoolInfo(pid).freezeTime;

        uint256 endTime = poolFreezeTime != 0
            ? poolFreezeTime
            : block.timestamp;

        // secondsPassed = number of seconds between lastClaimedTime and endTime
        uint256 secondsPassed = _getSecondsPassed(
            token.lastClaimedTime,
            endTime
        );
        newPending =
            (((token.amount * token.apy) / BPS) * secondsPassed) /
            YEAR;
        totalPending = newPending + token.unclaimed;
        actualPending = (totalPending * (BPS - saloonFee)) / BPS;

        return (totalPending, actualPending, newPending);
    }
}
