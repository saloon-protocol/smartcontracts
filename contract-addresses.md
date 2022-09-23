[8016924] MyScript::run()
├─ [0] VM::envUint(PRIVATE_KEY)
│ └─ ← 37449008748699929869015354562404715933579094355048093435875514585867822070191
├─ [0] VM::startBroadcast(37449008748699929869015354562404715933579094355048093435875514585867822070191)
│ └─ ← ()
├─ [465499] → new BountyProxy@0x146aB8ca06Ae86aD8F171Eed4CE9bAEb90998396
│ └─ ← 2325 bytes of code
├─ [393946] → new BountyProxyFactory@0x61497c6c7EffDf82E5023E48AbB54e86d0ad3185
│ ├─ emit OwnershipTransferred(previousOwner: 0x0000000000000000000000000000000000000000, newOwner: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc)
│ └─ ← 1849 bytes of code
├─ [2027617] → new BountyPool@0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF
│ ├─ emit OwnershipTransferred(previousOwner: 0x0000000000000000000000000000000000000000, newOwner: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc)
│ └─ ← 9866 bytes of code
├─ [216907] → new UpgradeableBeacon@0x1e103A435fC3231dB280B35eabe586967c00845c
│ ├─ emit OwnershipTransferred(previousOwner: 0x0000000000000000000000000000000000000000, newOwner: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc)
│ └─ ← 852 bytes of code
├─ [3302153] → new BountyProxiesManager@0xa5Ec2523dBA9C42E3ab62150dd2BbA55CC097767
│ └─ ← 16492 bytes of code
├─ [190161] → new ManagerProxy@0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7
│ ├─ emit Upgraded(implementation: BountyProxiesManager: [0xa5Ec2523dBA9C42E3ab62150dd2BbA55CC097767])
│ ├─ emit AdminChanged(previousAdmin: 0x0000000000000000000000000000000000000000, newAdmin: 0x00a329c0648769A73afAc7F9381E08FB43dBEA72)
│ └─ ← 708 bytes of code
├─ [24640] BountyPool::initializeImplementation(ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
│ ├─ emit Initialized(version: 1)
│ └─ ← ()
├─ [115437] ManagerProxy::initialize(BountyProxyFactory: [0x61497c6c7EffDf82E5023E48AbB54e86d0ad3185], UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c], BountyPool: [0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF])
│ ├─ [115033] BountyProxiesManager::initialize(BountyProxyFactory: [0x61497c6c7EffDf82E5023E48AbB54e86d0ad3185], UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c], BountyPool: [0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF]) [delegatecall]
│ │ ├─ emit OwnershipTransferred(previousOwner: 0x0000000000000000000000000000000000000000, newOwner: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc)
│ │ ├─ emit Initialized(version: 1)
│ │ └─ ← ()
│ └─ ← ()
├─ [73016] BountyProxy::initialize(UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c], 0x, ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
│ ├─ [308] UpgradeableBeacon::implementation() [staticcall]
│ │ └─ ← BountyPool: [0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF]
│ ├─ emit BeaconUpgraded(beacon: UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c])
│ ├─ emit AdminChanged(previousAdmin: 0x0000000000000000000000000000000000000000, newAdmin: ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
│ ├─ emit Initialized(version: 1)
│ └─ ← ()
├─ [47033] BountyProxyFactory::initiliaze(BountyProxy: [0x146aB8ca06Ae86aD8F171Eed4CE9bAEb90998396], ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
│ ├─ emit Initialized(version: 1)
│ └─ ← ()
├─ [23295] ManagerProxy::updateTokenWhitelist(0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, true)
│ ├─ [22894] BountyProxiesManager::updateTokenWhitelist(0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, true) [delegatecall]
│ │ └─ ← false
│ └─ ← false
├─ [348857] ManagerProxy::deployNewBounty(0x, YEEHAW, 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc)
│ ├─ [348423] BountyProxiesManager::deployNewBounty(0x, YEEHAW, 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc) [delegatecall]
│ │ ├─ [115978] BountyProxyFactory::deployBounty(UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c], 0x)
│ │ │ ├─ [9031] → new <Unknown>@0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e
│ │ │ │ └─ ← 45 bytes of code
│ │ │ ├─ [73203] 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e::initialize(UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c], 0x, ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
│ │ │ │ ├─ [73016] BountyProxy::initialize(UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c], 0x, ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7]) [delegatecall]
│ │ │ │ │ ├─ [308] UpgradeableBeacon::implementation() [staticcall]
│ │ │ │ │ │ └─ ← BountyPool: [0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF]
│ │ │ │ │ ├─ emit BeaconUpgraded(beacon: UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c])
│ │ │ │ │ ├─ emit AdminChanged(previousAdmin: 0x0000000000000000000000000000000000000000, newAdmin: ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
│ │ │ │ │ ├─ emit Initialized(version: 1)
│ │ │ │ │ └─ ← ()
│ │ │ │ └─ ← ()
│ │ │ └─ ← 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e
│ │ ├─ [26202] 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e::initializeImplementation(ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
│ │ │ ├─ [26033] BountyProxy::initializeImplementation(ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7]) [delegatecall]
│ │ │ │ ├─ [308] UpgradeableBeacon::implementation() [staticcall]
│ │ │ │ │ └─ ← BountyPool: [0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF]
│ │ │ │ ├─ [24640] BountyPool::initializeImplementation(ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7]) [delegatecall]
│ │ │ │ │ ├─ emit Initialized(version: 1)
│ │ │ │ │ └─ ← ()
│ │ │ │ └─ ← ()
│ │ │ └─ ← ()
│ │ ├─ emit DeployNewBounty(sender: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, \_projectWallet: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, newProxyAddress: 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e)
│ │ └─ ← 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e, true
│ └─ ← 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e, true
├─ [1644] ManagerProxy::getBountyAddressByName(YEEHAW) [staticcall]
│ ├─ [1237] BountyProxiesManager::getBountyAddressByName(YEEHAW) [delegatecall]
│ │ └─ ← 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e
│ └─ ← 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e
├─ [24453] 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889::approve(0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e, 100000000000000000000)
│ ├─ emit Approval(param0: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, param1: 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e, param2: 100000000000000000000)
│ └─ ← 0x0000000000000000000000000000000000000000000000000000000000000001
├─ [60531] ManagerProxy::projectDeposit(YEEHAW, 100000000000000000)
│ ├─ [60118] BountyProxiesManager::projectDeposit(YEEHAW, 100000000000000000) [delegatecall]
│ │ ├─ [56974] 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e::bountyDeposit(0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, 100000000000000000)
│ │ │ ├─ [56790] BountyProxy::bountyDeposit(0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, 100000000000000000) [delegatecall]
│ │ │ │ ├─ [308] UpgradeableBeacon::implementation() [staticcall]
│ │ │ │ │ └─ ← BountyPool: [0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF]
│ │ │ │ ├─ [55388] BountyPool::bountyDeposit(0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, 100000000000000000) [delegatecall]
│ │ │ │ │ ├─ [30884] 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889::transferFrom(0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e, 100000000000000000)
│ │ │ │ │ │ ├─ emit Transfer(param0: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, param1: 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e, param2: 100000000000000000)
│ │ │ │ │ │ └─ ← 0x0000000000000000000000000000000000000000000000000000000000000001
│ │ │ │ │ └─ ← true
│ │ │ │ └─ ← true
│ │ │ └─ ← true
│ │ └─ ← true
│ └─ ← true
├─ [0] VM::stopBroadcast()
│ └─ ← ()
└─ ← ()

# Script ran successfully.

Simulated On-chain Traces:

[555191] → new BountyProxy@0x146aB8ca06Ae86aD8F171Eed4CE9bAEb90998396
└─ ← 2325 bytes of code

[477718] → new BountyProxyFactory@0x61497c6c7EffDf82E5023E48AbB54e86d0ad3185
├─ emit OwnershipTransferred(previousOwner: 0x0000000000000000000000000000000000000000, newOwner: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc)
└─ ← 1849 bytes of code

[2237801] → new BountyPool@0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF
├─ emit OwnershipTransferred(previousOwner: 0x0000000000000000000000000000000000000000, newOwner: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc)
└─ ← 9866 bytes of code

[292111] → new UpgradeableBeacon@0x1e103A435fC3231dB280B35eabe586967c00845c
├─ emit OwnershipTransferred(previousOwner: 0x0000000000000000000000000000000000000000, newOwner: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc)
└─ ← 852 bytes of code

[3613773] → new BountyProxiesManager@0xa5Ec2523dBA9C42E3ab62150dd2BbA55CC097767
└─ ← 16492 bytes of code

[280765] → new ManagerProxy@0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7
├─ emit Upgraded(implementation: BountyProxiesManager: [0xa5Ec2523dBA9C42E3ab62150dd2BbA55CC097767])
├─ emit AdminChanged(previousAdmin: 0x0000000000000000000000000000000000000000, newAdmin: 0x00a329c0648769A73afAc7F9381E08FB43dBEA72)
└─ ← 708 bytes of code

[54038] BountyPool::initializeImplementation(ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
├─ emit Initialized(version: 1)
└─ ← ()

[150973] ManagerProxy::initialize(BountyProxyFactory: [0x61497c6c7EffDf82E5023E48AbB54e86d0ad3185], UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c], BountyPool: [0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF])
├─ [115033] BountyProxiesManager::initialize(BountyProxyFactory: [0x61497c6c7EffDf82E5023E48AbB54e86d0ad3185], UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c], BountyPool: [0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF]) [delegatecall]
│ ├─ emit OwnershipTransferred(previousOwner: 0x0000000000000000000000000000000000000000, newOwner: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc)
│ ├─ emit Initialized(version: 1)
│ └─ ← ()
└─ ← ()

[108438] BountyProxy::initialize(UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c], 0x, ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
├─ [2308] UpgradeableBeacon::implementation() [staticcall]
│ └─ ← BountyPool: [0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF]
├─ emit BeaconUpgraded(beacon: UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c])
├─ emit AdminChanged(previousAdmin: 0x0000000000000000000000000000000000000000, newAdmin: ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
├─ emit Initialized(version: 1)
└─ ← ()

[78222] BountyProxyFactory::initiliaze(BountyProxy: [0x146aB8ca06Ae86aD8F171Eed4CE9bAEb90998396], ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
├─ emit Initialized(version: 1)
└─ ← ()

[54577] ManagerProxy::updateTokenWhitelist(0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, true)
├─ [24894] BountyProxiesManager::updateTokenWhitelist(0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, true) [delegatecall]
│ └─ ← false
└─ ← false

[424886] ManagerProxy::deployNewBounty(0x, YEEHAW, 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc)
├─ [372423] BountyProxiesManager::deployNewBounty(0x, YEEHAW, 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc) [delegatecall]
│ ├─ [129478] BountyProxyFactory::deployBounty(UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c], 0x)
│ │ ├─ [9031] → new <Unknown>@0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e
│ │ │ └─ ← 45 bytes of code
│ │ ├─ [82703] 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e::initialize(UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c], 0x, ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
│ │ │ ├─ [80016] BountyProxy::initialize(UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c], 0x, ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7]) [delegatecall]
│ │ │ │ ├─ [2308] UpgradeableBeacon::implementation() [staticcall]
│ │ │ │ │ └─ ← BountyPool: [0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF]
│ │ │ │ ├─ emit BeaconUpgraded(beacon: UpgradeableBeacon: [0x1e103A435fC3231dB280B35eabe586967c00845c])
│ │ │ │ ├─ emit AdminChanged(previousAdmin: 0x0000000000000000000000000000000000000000, newAdmin: ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
│ │ │ │ ├─ emit Initialized(version: 1)
│ │ │ │ └─ ← ()
│ │ │ └─ ← ()
│ │ └─ ← 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e
│ ├─ [26202] 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e::initializeImplementation(ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7])
│ │ ├─ [26033] BountyProxy::initializeImplementation(ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7]) [delegatecall]
│ │ │ ├─ [308] UpgradeableBeacon::implementation() [staticcall]
│ │ │ │ └─ ← BountyPool: [0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF]
│ │ │ ├─ [24640] BountyPool::initializeImplementation(ManagerProxy: [0x90e4184234fc97f8004E4f4C210CC6F45A11b4d7]) [delegatecall]
│ │ │ │ ├─ emit Initialized(version: 1)
│ │ │ │ └─ ← ()
│ │ │ └─ ← ()
│ │ └─ ← ()
│ ├─ emit DeployNewBounty(sender: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, \_projectWallet: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, newProxyAddress: 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e)
│ └─ ← 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e, true
└─ ← 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e, true

[51859] 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889::approve(0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e, 100000000000000000000)
├─ emit Approval(param0: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, param1: 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e, param2: 100000000000000000000)
└─ ← 0x0000000000000000000000000000000000000000000000000000000000000001

[135084] ManagerProxy::projectDeposit(YEEHAW, 100000000000000000)
├─ [93418] BountyProxiesManager::projectDeposit(YEEHAW, 100000000000000000) [delegatecall]
│ ├─ [79774] 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e::bountyDeposit(0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, 100000000000000000)
│ │ ├─ [77090] BountyProxy::bountyDeposit(0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, 100000000000000000) [delegatecall]
│ │ │ ├─ [2308] UpgradeableBeacon::implementation() [staticcall]
│ │ │ │ └─ ← BountyPool: [0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF]
│ │ │ ├─ [64688] BountyPool::bountyDeposit(0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889, 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, 100000000000000000) [delegatecall]
│ │ │ │ ├─ [35684] 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889::transferFrom(0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e, 100000000000000000)
│ │ │ │ │ ├─ emit Transfer(param0: 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc, param1: 0x6cC8713205AEF64a84b43fc7b848Ad5Ac3b8E97e, param2: 100000000000000000)
│ │ │ │ │ └─ ← 0x0000000000000000000000000000000000000000000000000000000000000001
│ │ │ │ └─ ← true
│ │ │ └─ ← true
│ │ └─ ← true
│ └─ ← true
└─ ← true

==========================

Estimated total gas used for script: 11070060

Estimated amount required: 0.03321018042066228 ETH

==========================

###

Finding wallets for all the necessary addresses...

##

Sending transactions [0 - 13].
⠤ [00:00:13] [#######################################################################################################################################################################################################] 14/14 txes (0.0s)
Transactions saved to: /Users/vitorfrasson/code/Saloon/smartcontracts/broadcast/Deploy.s.sol/80001/run-latest.json

##

Waiting for receipts.
⠠ [00:00:08] [###################################################################################################################################################################################################] 14/14 receipts (0.0s)

#####

✅ Hash: 0x0cdeba7817fa70f7709068131e3027b570ba2fbc2a5ca92b684c491405eaf0ad
Contract Address: 0x146ab8ca06ae86ad8f171eed4ce9baeb90998396
Block: 28248509
Paid: 0.001665573010548629 ETH (555191 gas \* 3.000000019 gwei)

#####

✅ Hash: 0x138e0171b187a9da961da9bb9a7d66c6205daa54d40ee67ecd19a0ee4e926292
Contract Address: 0x61497c6c7effdf82e5023e48abb54e86d0ad3185
Block: 28248509
Paid: 0.001433154009076642 ETH (477718 gas \* 3.000000019 gwei)

#####

✅ Hash: 0x19594ab2933a23543b538a4220a9a7fd5d142c643f1063be1fc41d69e97cc833
Contract Address: 0xaba8aecb8d60fe44ec9fd5afcb73eca9ab301fdf
Block: 28248509
Paid: 0.006713403042518219 ETH (2237801 gas \* 3.000000019 gwei)

#####

✅ Hash: 0xd0aea192e8d7460477b3360556336ea3a2731892e7870005302a8ae5da490652
Contract Address: 0x1e103a435fc3231db280b35eabe586967c00845c
Block: 28248509
Paid: 0.000876333005550109 ETH (292111 gas \* 3.000000019 gwei)

#####

✅ Hash: 0xed7d868847e288ff5290ae355c1bdca375f6ba8158fa0e6a8feb86e995aa4412
Contract Address: 0xa5ec2523dba9c42e3ab62150dd2bba55cc097767
Block: 28248509
Paid: 0.010841319068661687 ETH (3613773 gas \* 3.000000019 gwei)

#####

✅ Hash: 0x5d93ec13354dc61eae73b08d486a521576d2f5b87b5caa13e43fefefc6a35e34
Contract Address: 0x90e4184234fc97f8004e4f4c210cc6f45a11b4d7
Block: 28248509
Paid: 0.000842295005334535 ETH (280765 gas \* 3.000000019 gwei)

#####

✅ Hash: 0x086f0708aac3b2f099b4eed39c9ee37e8914c51495e86a7a99c1b9249d4060a5
Block: 28248509
Paid: 0.00015258000096634 ETH (50860 gas \* 3.000000019 gwei)

#####

✅ Hash: 0xfe44fb34d26dbd3c35d8297562dbbe4317ea680b755e2841494e6e7dabe2c54a
Block: 28248511
Paid: 0.00042627900284186 ETH (142093 gas \* 3.00000002 gwei)

#####

✅ Hash: 0x53a3242b1fa120d75b24af034efb2f0af2c96c2517b1de427ac189f1f369b300
Block: 28248511
Paid: 0.0003061800020412 ETH (102060 gas \* 3.00000002 gwei)

#####

✅ Hash: 0x4b4e361cad7dcc860f9916425c26b9b7e6272386b7b2e318a221ab091fb63fbd
Block: 28248511
Paid: 0.00022086300147242 ETH (73621 gas \* 3.00000002 gwei)

#####

✅ Hash: 0x5258092693cce80b948c7cf0c7ee35611f41146bca2a814574189788ce0d760d
Block: 28248511
Paid: 0.00015410100102734 ETH (51367 gas \* 3.00000002 gwei)

#####

✅ Hash: 0x72995e4096221859a39a1ce7031703becc1977a5116c286ca6b57fde32820138
Block: 28248511
Paid: 0.00119967900799786 ETH (399893 gas \* 3.00000002 gwei)

#####

✅ Hash: 0xa84de9583a61cb22027b486f426dec3c76a20d732a654e1eb340a4fd3dec21e5
Block: 28248511
Paid: 0.00013829100092194 ETH (46097 gas \* 3.00000002 gwei)

#####

✅ Hash: 0x7254865d467e10b649076e7e68b79670a10bb74a20ea5aadee087eec80af6fe3
Block: 28248511
Paid: 0.0003602250024015 ETH (120075 gas \* 3.00000002 gwei)

Transactions saved to: /Users/vitorfrasson/code/Saloon/smartcontracts/broadcast/Deploy.s.sol/80001/run-latest.json

==========================

ONCHAIN EXECUTION COMPLETE & SUCCESSFUL. Transaction receipts written to "/Users/vitorfrasson/code/Saloon/smartcontracts/broadcast/Deploy.s.sol/80001/run-latest.json"
Total Paid: 0.025330275161360281 ETH (8443425 gas \* avg 3.000000019 gwei)

We haven't found any matching bytecode for the following contracts: [0x146ab8ca06ae86ad8f171eed4ce9baeb90998396, 0x1e103a435fc3231db280b35eabe586967c00845c, 0x90e4184234fc97f8004e4f4c210cc6f45a11b4d7, 0x6cc8713205aef64a84b43fc7b848ad5ac3b8e97e].

This may occur when resuming a verification, but the underlying source code or compiler version has changed.

##

Start verification for (3) contracts

Submitting verification for [src/BountyProxyFactory.sol:BountyProxyFactory] "0x61497c6c7EffDf82E5023E48AbB54e86d0ad3185".

Submitting verification for [src/BountyProxyFactory.sol:BountyProxyFactory] "0x61497c6c7EffDf82E5023E48AbB54e86d0ad3185".
Submitted contract for verification:
Response: `OK`
GUID: `zkspizddb4tffrafgbvwbkdxcxynj23gc6eksgjinqph3hhkqd`
URL:
https://mumbai.polygonscan.com/address/0x61497c6c7effdf82e5023e48abb54e86d0ad3185
Waiting for verification result...
Contract successfully verified

Submitting verification for [src/BountyPool.sol:BountyPool] "0xAbA8aeCB8d60fe44EC9fD5AfCb73EcA9aB301fDF".
Submitted contract for verification:
Response: `OK`
GUID: `1dj2tn8vcm1gj92d3alppbscgbmvuufdy61qyadrcxuxhy6efr`
URL:
https://mumbai.polygonscan.com/address/0xaba8aecb8d60fe44ec9fd5afcb73eca9ab301fdf
Waiting for verification result...
Contract successfully verified

Submitting verification for [src/BountyProxiesManager.sol:BountyProxiesManager] "0xa5Ec2523dBA9C42E3ab62150dd2BbA55CC097767".
Submitted contract for verification:
Response: `OK`
GUID: `t7aukduyghhc7kwqqqtwjvhx1837hb3tntbnj8rgkumqnkupms`
URL:
https://mumbai.polygonscan.com/address/0xa5ec2523dba9c42e3ab62150dd2bba55cc097767
Waiting for verification result...
Contract successfully verified
All (3) contracts were verified!

Transactions saved to: /Users/vitorfrasson/code/Saloon/smartcontracts/broadcast/Deploy.s.sol/80001/run-latest.json
