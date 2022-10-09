# Saloon Smart Contracts Layout

The only entry point to interact with the Saloon smart contracts is through the `Manager` address.

- Projects can make and withdraw their bounty deposits.
- Investors can stake and unstake
- Admins can deploy and manage bounties.

```mermaid
graph TD;
    Admin-->Manager
    Admin-. deployBounty .->Manager
    User-->Manager
    Manager---->BountyProxy
    Manager-..-Factory
    Factory-...->Bounty


    subgraph Bounty
    BountyProxy-- delegatecall --->Implementation
    BountyProxy-. getAddress .->Beacon
    Beacon-. Implementation Address .->BountyProxy
    end

```
