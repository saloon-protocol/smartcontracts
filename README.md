# Saloon Smart Contracts Layout

The only entry point to interact with the Saloon smart contracts is through the `Manager` address.

- Projects can make and withdraw their bounty deposits.
- Investors can stake and unstake
- Admins can deploy and manage bounties.

```mermaid
%%{init: { "theme": "neutral" } }%%
graph TD;
    subgraph Overview
        Admin-. deployBounty ..-ManagerProxy[\ManagerProxy/]
        Admin((Admin))-- Interact with Bounty ----ManagerProxy[\ManagerProxy/]


        User((User))-- Interact with Bounty ----ManagerProxy[\ManagerProxy/]

        ManagerProxy-...-Factory
        Factory -.-> BountyProxy
        Factory -.-> BountyProxy2

        subgraph Manager
        ManagerProxy<-- delegatecall -->Implementation[Manager Implementaion]
        end

        ManagerProxy--->BountyProxy

        subgraph Bounty
        BountyProxy
        end

        subgraph Bounty2
        BountyProxy2[BountyProxy]
        end
    BountyProxy2 -. get Implementation address .-> Beacon

    BountyProxy -. get Implementation address .-> Beacon
    BountyProxy-- delegatecall --->Pool[Bounty Implementation]
    BountyProxy2[BountyProxy]-- delegatecall --->Pool[Bounty Implementation]




    end

    linkStyle 1,2,7 fill:none,stroke-width:2px,stroke:blue
    linkStyle 0,3,4,5 fill:none,stroke-width:2px,stroke:green
    linkStyle 6,8,10 fill:none,stroke-width:2px,stroke:brown


    style Manager fill:#000,color:#fff,arrow-head:#fff
    style Bounty fill:#000,color:#fff,arrow-head:#fff
    style Bounty2 fill:#000,color:#fff,arrow-head:#fff



```

### Upgrading Proxy Implementation Contract

- Changing the ManagerProxy implementation is done by calling the current implementation which updates itself.

- All bounty proxies refer to the same implementation address via the Beacon. Therefore changing the address the Beacon refers to will update the implementation address for all bounty proxies.

```mermaid
%%{init: { "theme": "neutral" } }%%
graph TD;
    subgraph Upgrading Implementation Contracts
        Admin((Admin))-- Upgrade Manager Implementation ----ManagerProxy[\ManagerProxy/]
        Admin-- Upgrade Bounty Implementation ----ManagerProxy

        subgraph Manager
        ManagerProxy-- delegatecall -->Implementation[Manager Implementaion]
        Implementation-- upgradeTo -->Implementation
        end

        ManagerProxy --> Beacon
    end

    linkStyle 0,1,2,3 fill:none,stroke-width:2px,stroke:orange
    linkStyle 1,4 fill:none,stroke-width:2px,stroke:brown


    style Manager fill:#000,color:#fff,arrowheadPath:#fff
```
