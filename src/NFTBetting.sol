//SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/* TODO:
- implement safe transfers 
- implement support for fee-on-transfer
- implement events

TODO2:

Implement different betting and withdraw functions for different betting options:
NFT vs NFT option
CASH vs CASH option
CASH vs NFT option
NFT vs CASH currently supported
*/

// NOTE: using blocktimestamp might be unnecessary if we are constantly updating matches when they end.

contract NFTBetting is ReentrancyGuard, Ownable {
    //#################### State Variables *****************\\
    uint256 betCount;
    uint256 internal constant matchLength = 95 minutes;

    enum Winner {
        NA,
        HOME,
        AWAY,
        DRAW
    }

    struct BetDetails {
        address maker;
        address taker;
        address token;
        address paymentToken;
        uint256 tokenId;
        uint256 minPayment;
        uint256 matchId;
        Winner makerToWin;
        Winner takerToWin;
        bool betTaken;
        bool validBet;
        bool paid;
    }
    // betId => bet details
    mapping(uint256 => BetDetails) internal betIdDetails;

    struct MatchDetails {
        Winner matchWinner;
        uint256 matchStart;
        uint256 matchEnds;
        bool validId;
    }
    // matchId => match details
    mapping(uint256 => MatchDetails) internal matchIdDetails;

    //#################### State Variables END *****************\\

    // Update new matches available for betting
    // Updates in batch
    // Front end calls this function to update results of matches.
    // It also updates future matches that are available to bet in
    function updateMatches(
        uint256[] calldata _matchId,
        uint256[] calldata _matchStart,
        Winner[] calldata _matchWinner
    ) external onlyOwner {
        uint256 arrayLength = _matchId.length;
        require(
            arrayLength == _matchStart.length &&
                arrayLength == _matchWinner.length,
            "Legnth doenst match"
        );

        for (uint256 i; i < arrayLength; ) {
            matchIdDetails[_matchId[i]].matchWinner = _matchWinner[i];
            // Including timestamp might no be necessary but doing it for now
            matchIdDetails[_matchId[i]].matchEnds =
                _matchStart[i] +
                matchLength;
            matchIdDetails[_matchId[i]].matchStart = _matchStart[i];
            matchIdDetails[_matchId[i]].validId = true;
            unchecked {
                ++i;
            }
        }
    }

    //#################### Betting Functions *****************\\

    // Start bet
    function betNFT(
        address _token,
        uint256 _tokenId,
        uint256 _minPayment,
        uint256 _matchId,
        Winner _winner,
        address _paymentToken
    ) external nonReentrant returns (bool) {
        require(_minPayment > 0, "Minimum Payment too low");
        require(_winner > Winner.NA, "No winner chosen");
        require(
            matchIdDetails[_matchId].matchEnds < block.timestamp,
            "Match not available"
        );
        require(
            matchIdDetails[_matchId].matchWinner == Winner.NA,
            "Winner already chosen"
        );

        require(matchIdDetails[_matchId].validId == true, "Invalid match id");

        ERC721(_token).transferFrom(msg.sender, address(this), _tokenId);
        betCount++;
        betIdDetails[betCount].validBet = true;
        betIdDetails[betCount].token = _token;
        betIdDetails[betCount].tokenId = _tokenId;
        betIdDetails[betCount].minPayment = _minPayment;
        betIdDetails[betCount].paymentToken = _paymentToken;
        betIdDetails[betCount].matchId = _matchId;
        betIdDetails[betCount].makerToWin = _winner;
        return true;
    }

    // Take Bet
    function takeBet(
        uint256 _betCount,
        uint256 _payment,
        Winner _takerToWin
    ) external payable nonReentrant returns (bool) {
        // cache betIdDetails
        BetDetails memory betDetails = betIdDetails[_betCount];

        // check bet is valid
        require(betDetails.validBet == true, "Bet Non-existent");
        // check bets are not the same and team outcome has been picked
        require(
            betDetails.makerToWin != _takerToWin && _takerToWin != Winner.NA,
            "Cant bet on the same outcome"
        );
        betIdDetails[_betCount].takerToWin = _takerToWin;
        // check payment >= min payment, or if bet is taken, payment is higher than current
        if (betDetails.betTaken == false) {
            require(_payment >= betDetails.minPayment, "Not enough Payment");

            // change bet status to taken
            betIdDetails[_betCount].betTaken = true;
            // update taker address
            betIdDetails[_betCount].taker = msg.sender;

            // transfer tokens to this account
            if (betDetails.paymentToken == address(0x0)) {
                // if msg.value > payment difference is not reimbursed
                require(msg.value >= _payment, "Not enough payment");
                // update payment
                betIdDetails[_betCount].minPayment = msg.value;
            } else {
                require(msg.value == 0, "ERC20 payment only");

                // ERC20 transfer - NOTE: use safeTransferFrom
                ERC20(betDetails.paymentToken).transferFrom(
                    msg.sender,
                    address(this),
                    _payment
                );
                // update payment
                betIdDetails[_betCount].minPayment = _payment;
            }
            return true;

            // if bet has already been taken
        } else {
            // NOTE: have minimum raise of 5% if bet is taken?
            require(_payment > betDetails.minPayment, "Payment not enough");
            // update taker address
            betIdDetails[_betCount].taker = msg.sender;

            // transfer tokens to this account
            if (betDetails.paymentToken == address(0x0)) {
                // if msg.value > payment difference is not reimbursed
                require(msg.value >= _payment, "Not enough payment");
                // update payment
                betIdDetails[_betCount].minPayment = msg.value;
            } else {
                require(msg.value == 0, "ERC20 payment only");

                // ERC20 transfer - NOTE: use safeTransferFrom
                ERC20(betDetails.paymentToken).transferFrom(
                    msg.sender,
                    address(this),
                    _payment
                );
                // update payment
                betIdDetails[_betCount].minPayment = _payment;
            }
            return true;
        }
    }

    // cancel Bet
    function cancelBet(uint256 _betCount) external returns (bool) {
        // cache betIdDetails
        BetDetails memory betDetails = betIdDetails[_betCount];

        // check to see if sender is maker
        require(betDetails.maker == msg.sender, "You havent made the bet");
        // check if bet isnt taken
        require(betDetails.betTaken == false, "Bet already taken");
        // if match not over fee has to be paid
        if (matchIdDetails[betDetails.matchId].matchEnds < block.timestamp) {
            // cancel bet
            betIdDetails[_betCount].validBet = false;
            // transfer token back to sender with fee
            return true;
        } else {
            // cancel bet
            betIdDetails[_betCount].validBet = false;
            // transfer token back to sender without any fees
        }
        return true;
    }

    // Withdraw earnings
    // Winner pays fees
    function withdrawEarnings(uint256 _betCount)
        external
        nonReentrant
        returns (bool)
    {
        BetDetails memory betDetails = betIdDetails[_betCount];

        // check winner has been selected
        require(
            matchIdDetails[betDetails.matchId].matchWinner != Winner.NA,
            "Winner not selected"
        );
        // it hasnt been paid yet
        require(betIdDetails[_betCount].paid == false, "Has already been paid");

        // check if sender = winner
        // if sender = maker
        if (msg.sender == betDetails.maker) {
            // check if winner is maker
            if (
                matchIdDetails[betDetails.matchId].matchWinner ==
                betDetails.makerToWin
            ) {
                // transfer earnings minus fee
                // check if token is native or not
                betIdDetails[_betCount].paid = true;
                return true;
            }
        }
        // if sender = taker
        else {
            // check if winner is taker
            if (
                matchIdDetails[betDetails.matchId].matchWinner ==
                betDetails.takerToWin
            ) {
                // transfer earnings minus fee
                // check if token is native or not
                betIdDetails[_betCount].paid = true;
                return true;
            }
        }
        // if nobody won, both pay fee based on cash amount
        //for tests now it'll just be taken out of cash better though
        uint256 repayment = betDetails.minPayment / 2;
        // pay according to payment Token
        if (betDetails.paymentToken == address(0x0)) {
            // TODO INSERT CALL VALUE = minPayment/2
            (bool sent, ) = betDetails.taker.call{value: repayment}("");
            require(sent == true, "Call failed");
            (bool success, ) = betDetails.maker.call{value: repayment}("");
            require(success == true, "Call failed");
            betIdDetails[_betCount].paid = true;
            return true;
        } else {
            // calculate payment
            // pay with ERC20
            ERC20(betDetails.paymentToken).transferFrom(
                betDetails.maker,
                address(this),
                repayment
            );
            ERC20(betDetails.paymentToken).transferFrom(
                betDetails.taker,
                address(this),
                repayment
            );
            betIdDetails[_betCount].paid = true;
            return true;
        }
    }

    // Batch start Bet
    // Batch take Bet

    //#################### Betting Functions END *****************\\

    //#################### View Functions *****************\\

    // view bet maker/taker

    // view which bets address has participated in
}
