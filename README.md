What am i trying to build?

Two Contratcs:

- Bounty Pool factory - All bounties are going to be pools.
- Pool contract

Factory that Deploys a bounty pool for frontend to fetch values from.

---

Pool Factory + Registry or Factory already registers all pools deployed?:

- Only we can deploy a bounty pool

---

Bounty Pool= Bounty Pool Proxy + Implementation Contract

- Project needs to be able to set APY
- Investors need to be able to invest in pool
- Investing and Withdrawing locking mechanisms
- Pool funds staking mechanism

- Bounty Pools implementations will change in the future to accomodate Options + NFTs.

---

Considerations:

- Options/NFTs should be able to read pool value, easy.
- Insurance Pool we be its own thing. With its own factory.
