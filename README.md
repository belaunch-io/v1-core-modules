# v1-core-modules

![Banner](https://dev-sui.belaunch.io/assets/banner.5ab71a7e.png)

[![Actions Status](https://github.com/Uniswap/uniswap-v2-core/workflows/CI/badge.svg)](https://github.com/Uniswap/uniswap-v2-core/actions)

This repo contains in-depth Smart Contracts used in BeLaunch on 💧SUI.

## Existing modules

| Module name                                                          | Description                                                                                                                |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------|
| [Token Generator](./SUI_MOVE/coins)                                   | Create coin according to 0x2::coin standard                                                                               |
| [BeLock](./SUI_MOVE/locked)                                           | Coins & LPs Locker                                                                                                        |
| [BeNFTs](./SUI_MOVE/NFTs)                                             | NFTs Minter & Manager                                                                                                     |
| [NFTs Marketplace](./SUI_MOVE/marketplace)                            | NFTs Marketplace allows users to freely buy and sell NFTs                                                                 |
| [NFTs Store](./SUI_MOVE/store)                                        | Create an NFT store and issue NFTs for the first time (INO)                                                               |
| [BeDEX](./SUI_MOVE/swap)                                              | Based on Uniswap V2, it combines peripheral and core trading and liquidity protocols                                      |
| [BeStake](./SUI_MOVE/stake)                                           | Stake BLAT flexibly and get projects’ tokens as rewards                                                                   |
