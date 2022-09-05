BountyProxyFactory deploys bounty proxies which all look to the same upgradeable beacon.
We can upgrade all proxies by changing which contract the beacon is looking to.

---

Two main Contratcs:

- Bounty Pool factory - All bounties are going to be pools.
- Pool contract

Factory that Deploys a bounty pool for frontend to fetch values from.

---

BountyProxyFactory + Registry?:

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
