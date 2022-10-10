# Saloon Smart Contracts Layout

The only entry point to interact with the Saloon smart contracts is through the `Manager` address.

- Projects can make and withdraw their bounty deposits.
- Investors can stake and unstake
- Admins can deploy and manage bounties.

```mermaid
%%{init: { "theme": "neutral" } }%%
graph TD;
    subgraph Overview
        Admin((Admin))-- Interact with Bounty ----Manager[\Manager/]
        style Manager fill:#000,color:#fff,arrow-head:#fff
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
    linkStyle 0,1,3,6 fill:none,stroke-width:1px,stroke:blue
    linkStyle 2,4,5,7 fill:none,stroke-width:1px,stroke:green

```

<style>
    #L-Manager-BountyProxy .arrowheadPath {
         fill:red !important;
    }
</style>
