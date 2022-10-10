# Saloon Smart Contracts Layout

The only entry point to interact with the Saloon smart contracts is through the `Manager` address.

- Projects can make and withdraw their bounty deposits.
- Investors can stake and unstake
- Admins can deploy and manage bounties.

```mermaid
graph TD;
    subgraph Overview
        Admin((Admin))-- Interact with Bounty ----Manager[\Manager/]
        style Admin fill:#f9f, defaultLinkColor:#f9f
        style Manager fill:#bbf, lineColor:#f9f
        User((User))-- Interact with Bounty ----Manager
        Admin-. deployBounty ..-Manager
        Manager--->BountyProxy
        Manager-.-Factory
        Factory -.-> BountyProxy


        subgraph Bounty
        BountyProxy-- delegatecall --->Implementation
        BountyProxy -. get Implementation address .-> Beacon
        end
    end

```
