# Collection of TODOs, Thoughts and Observations

[forge](https://book.getfoundry.sh/forge/)

## Basic Flow

The Manager contract controls it all, it is the only contract that we and any users have to interact with. This makes it simple and straightforward, not juggling different contracts addresses on front end or anything, just need to keep track of this one.

- It is able to:

  - Deploy new bounties.
  - Shutdown bounties
  - Deploy new implementations.
  - Update UpgradeableBeacon.

- Portal for users and projects:
  - Users are able to invest through it and claim their premiums.
  - Projects are able to control their deposits, APYs and pool caps.
  - We are able to pay bounties and claim insurance premiums.

## Questions:

- Should the Manager itself be a proxy? Seems like a good idea.

### TODOs big picture:

- Figure out Beacon Proxy implementation and Upgradeable Beacon. - DONE
- Develop BeaconProxy (bountyProxy) - DONE
- Develop UpgradeableBeacon - DONE
- Develop ProxyFactory - DONE
- Finish BountyProxiesManager Implementation
- Develop ManagerProxy
- Remove accounting redundancies between factory/registry/manager
- Make sure all contracts have working dependencies
- Test on testnet
- Test on mainnet

- Start Working on version 2

### TODOs by Contract:

BountyPool:

- EVENTS (and small todos)

---

BountyProxy:

- Only allow `manager` to call `delegate` -> Sort out if this is going to be done via ProxyFactory `transferOwnership` or `initialize()`. Probably initialize

---

UpgradeableBeacon:

---

BeaconProxyFactory:

- Only allow `manager` to deploy

---

Manager Implementation:

- function to dpeloy BountyProxyBase ( base to generate proxies from)
- function to deploy implementation (and update upgradeableBeacon atomically)
- function to deploy upgradeableBeacon
- function to change implementation on upgradeableBeacon

---

ManagerProxy:

- function to change implementation

## Ramblings, notes and observations

BountyProxyFactory deploys bounty proxies which all look to the same upgradeable beacon.
We can upgrade all proxies by changing which contract the beacon is looking to.

---

### Reasons/options for Manager -> Implementation access control choice

- The implementation will only accept calls coming from the `manager` contract.

- Every BountyProxy will have a different address so the Implementation cant rely on msg.sender and instead has to rely on receiving an extra input `_sender`

- Verifying senders can be done in two way

  - manager updates a mapping in the implementation contract every time a new BountyPool is launched so the Proxy can have access to the implementation. Proxy checks if mapping(`msg.sender`) is allowed (!=0) - THIS IS THE CHOSEN ONE.

  - OR instead of the manager updating the implementation contract with new values for every bounty that is launched, it just passes its address -- MEEH THIS WOULDNT WORK. Anyone could then call and pass in the managers address.

---

### Considerations

- Should we have a `_gap` in proxy/implementaion? I've seen somewhere it is good to avoid storage collisions.

---

Three/Four? main Contratcs:

- Registry (maybe rename it to Manager) - keeps tracks of proxies deployed and factories being used?
- Bounty Proxy factory - All bounties are going to be pools.
- Pool contract
- Bounty Manager? - allows us to manage all bounties from one contract? - Should this just be done in the registry? - Probably just add this functionality to registry

Factory that Deploys a bounty pool for frontend to fetch values from.

---

Registry:

- Needs to have public array and view function to view all deployed bounties so we can reference it in the future to deploy an insurance pool to all of them.
- Needs kill/retire function to cancel all actions on registry when/if we migrate

When updating to a new Registry:

- New registry can read state of this one on construction (e.g read bountyproxies addresses and their owners, copy it to new registry storage and launch insurance pool to every bountyproxy). Also the ability to change owners for bountyproxie and insuranceproxies?

- Ability to deploy bountyproxy + insuranceproxy simultaneously or individually. If an owner already has a bounty or insurance proxy we cant launch another one to prevent double accounting/ double pools

Summary/requirements:

- public facing array of bountyproxies+owner
- kill switch that applies to all admin functions like `deployBounty()`
- Factory address

---

BountyProxyFactory

- Only we can deploy a bounty pool

MIMO references:

- ProxyFactory: https://github.com/code-423n4/2022-08-mimo/blob/main/contracts/proxy/MIMOProxyFactory.sol

- ProxyRegistry: https://github.com/code-423n4/2022-08-mimo/blob/main/contracts/proxy/MIMOProxyRegistry.sol

- Proxy: https://github.com/code-423n4/2022-08-mimo/blob/main/contracts/proxy/MIMOProxy.sol

- Findings: https://docs.google.com/spreadsheets/d/1F95EzhI8vIE5X4JLH39MYI-t2y4ndRxu3yh568H1fV0/edit#gid=0

---

Bounty Pool= BountyProxy + Implementation Contract (Bounty.sol)

- Project needs to be able to set APY
- Investors need to be able to invest in pool
- Investing and Withdrawing locking mechanisms
- Pool funds staking mechanism

- Bounty Pools implementations will change in the future to accomodate Options + NFTs.

Use Beacon Proxy: https://docs.openzeppelin.com/contracts/4.x/api/proxy

Considerations:

- Options/NFTs should be able to read pool value, easy.
- Insurance Pool we be its own thing. With its own factory.

Managing APY Payments:

Project must have sufficient balance to pay maximum APY cost at all times.
We will transferFrom() the APY amount from projects regularly to top up their current balances.
If transfer fails the APY will be set as the current premiumBalance to insuranceCAP ratio.

- projects can increase APY at any time and it will be recorded in the APYperiods array including the time stamp. This array will be reference when stakers are claiming their premium.
- Keep track of stakers balance during different time stamps so we can calculate their balance at each APY period.

- APY is always set based on premiumBalance/insuranceCap
- If projects want to keep a high APY they must keep the premiumBalance up to date

- premiumBalance can never exceed monthly insuranceCAP

- how to keep track of APY through premium balance and still be able to handle interest claims at the same time?
- If pool fails to PAY desired APY current APY is set as default.

What happens if project decides to decrease full poolCap?

-- What if I implement paypremium based on stakerDeposit, APY and poolCap and transfer premium directly to stakers so they dont have to claim anything...
We would be transferring TO A LOT OF USERS, not gas efficient and would need many transactions to get it done to avoid gas limits.

- What if I still use stakerDeposit, APY and poolCap and transfer it to contracts address? How is this different from using premiumBalance?
  Project would only ever need to pay waht is necessary instead of full APY....
  But what happens if they dont pay?
  - Premium is paid on what APY the current premiumBalance allows, APY is reset to whatever premiumBalance dictates

ClaimPremium:

- if last time premium was called > 1 period

- loop through APY periods (reversely) until missed period is found

  - calculate size of missed APY periods
    - iterate through missed APY periods
      - check state balance of that period
      - calculate APYperday
        -multiply by period length
    - sum to Total accruedpremium

- transfer to staker
- if transfer fails:
  - call payPremium to top up address balance
  - transfer to staker
  - if this transfer fails:
    - decrease APY to premium balance and pay him whatever we can?

PayPremium:

- what if full pool goes a full period without payment?
  - payPremium is called if claimPremium drains contract out of balance!!

---

General Flow:

Registry is called to deploy
Registry calls factory
Factory deploys BountyProxy

How to retroactively deploy insurance pool for all bountyproxies?

---

Unstake():

- include timelock in staker struct

OBS:

- Stake only push to array if previous balance = 0
- Unstake removes from array if resulting balance = 0

---

Saloon Global Staking (Future Feature):

- Average APY from all Pools
- Split staking amount equally among all pools
- If one pool pays a bounty and its value decreases by 50%, the same happens to the equivalent amount of the user.
  Example:
- Total number of pools 10
- User staking amount $10
- Average APY of the 10 pools = 10%

- Pool #2 pays bounty and now instead of holding a total of 100K, it only has 50K
- User staking amount decreases from 10 to 9.5
