TODO:

- Check mapping array storage in REMIX
  have mapping array
  OR
  have struct with three arrays for counting, project and bounty addresses
  OR
  have mapping of mapping with the key being a uint incremented with number of bounties. constructors could loop through all mappings by referencing the total number of bounty proxies

BountyProxyFactory deploys bounty proxies which all look to the same upgradeable beacon.
We can upgrade all proxies by changing which contract the beacon is looking to.

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

TODO:

- Finish all functions.
- Implement events

---

General Flow:

Registry is called to deploy
Registry calls factory
Factory deploys BountyProxy

How to retroactively deploy insurance pool for all bountyproxies?

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
