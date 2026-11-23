# API route inventory

Generated from `packages/server/src/server.ts` (242 routes).
Errors use `{ "error": string }`; the string may be an error code or a readable message. Detailed schemas: [private PvE map](openapi.pve.yaml) and [Combat v2](openapi.combat-v2.yaml). PvE mutations require `Idempotency-Key`; map reads settle due arrivals. This inventory lists the remaining API coverage.

| Method | Path | Auth | Feature |
|---|---|---|---|
| GET | `/api/account/identities` | Bearer | — |
| POST | `/api/account/identities` | Bearer | — |
| DELETE | `/api/account/identities/:provider` | Bearer | — |
| POST | `/api/account/recovery-token` | Bearer | — |
| POST | `/api/achievements/:code/claim` | Bearer | — |
| GET | `/api/admin/analytics` | admin key | — |
| GET | `/api/admin/analytics/:section` | admin key | — |
| GET | `/api/admin/audit-logs` | admin key | — |
| GET | `/api/admin/banners` | admin key | — |
| POST | `/api/admin/banners` | admin key | — |
| PATCH | `/api/admin/banners/:bannerId` | admin key | — |
| POST | `/api/admin/banners/:bannerId/activate` | admin key | — |
| POST | `/api/admin/banners/:bannerId/deactivate` | admin key | — |
| PUT | `/api/admin/banners/:bannerId/pool` | admin key | — |
| PUT | `/api/admin/banners/:bannerId/schedule` | admin key | — |
| GET | `/api/admin/configs` | admin key | — |
| POST | `/api/admin/configs` | admin key | — |
| POST | `/api/admin/configs/:configId/activate` | admin key | — |
| GET | `/api/admin/configs/active` | admin key | — |
| GET | `/api/admin/content/enemies` | admin key | — |
| POST | `/api/admin/content/enemies` | admin key | — |
| GET | `/api/admin/content/hero-skills` | admin key | — |
| POST | `/api/admin/content/hero-skills` | admin key | — |
| GET | `/api/admin/content/heroes` | admin key | — |
| POST | `/api/admin/content/heroes` | admin key | — |
| POST | `/api/admin/content/heroes/:code/stats` | admin key | — |
| GET | `/api/admin/content/items` | admin key | — |
| POST | `/api/admin/content/items` | admin key | — |
| GET | `/api/admin/events` | admin key | — |
| POST | `/api/admin/events` | admin key | — |
| POST | `/api/admin/events/:eventId/activate` | admin key | — |
| POST | `/api/admin/events/:eventId/close` | admin key | — |
| POST | `/api/admin/events/:eventId/missions` | admin key | — |
| POST | `/api/admin/iap/refund` | admin key | — |
| GET | `/api/admin/iap/transactions` | admin key | — |
| POST | `/api/admin/leaderboards/:board/close` | admin key | — |
| GET | `/api/admin/leaderboards/seasons` | admin key | — |
| POST | `/api/admin/mailbox/send` | admin key | — |
| GET | `/api/admin/monitoring` | admin key | — |
| GET | `/api/admin/players` | admin key | — |
| GET | `/api/admin/players/:accountId` | admin key | — |
| POST | `/api/admin/players/:accountId/compensation` | admin key | — |
| POST | `/api/admin/players/:accountId/restore` | admin key | — |
| POST | `/api/admin/players/:accountId/restrict` | admin key | — |
| GET | `/api/admin/security-alerts` | admin key | — |
| POST | `/api/admin/security-alerts/:alertId/resolve` | admin key | — |
| GET | `/api/admin/shop` | admin key | — |
| POST | `/api/admin/shop/items` | admin key | — |
| GET | `/api/admin/support/tickets` | admin key | — |
| GET | `/api/admin/support/tickets/:ticketId` | admin key | — |
| POST | `/api/admin/support/tickets/:ticketId/reply` | admin key | — |
| POST | `/api/admin/support/tickets/:ticketId/status` | admin key | — |
| GET | `/api/alchemy` | Bearer | — |
| DELETE | `/api/alliance` | Bearer | — |
| GET | `/api/alliance` | Bearer | — |
| POST | `/api/alliance` | Bearer | — |
| GET | `/api/alliance/chat` | Bearer | — |
| POST | `/api/alliance/chat` | Bearer | — |
| POST | `/api/alliance/join` | Bearer | — |
| POST | `/api/alliance/leave` | Bearer | — |
| POST | `/api/alliance/members/:masterId/manage` | Bearer | — |
| PATCH | `/api/alliance/notice` | Bearer | — |
| POST | `/api/alliance/requests/:requestId/cancel` | Bearer | — |
| GET | `/api/alliance/search` | Bearer | — |
| POST | `/api/alliance/tech/upgrade` | Bearer | — |
| GET | `/api/alliance/wars` | Bearer | — |
| POST | `/api/alliance/wars` | Bearer | — |
| GET | `/api/alliance/wars/:warId` | Bearer | — |
| POST | `/api/auth/login` | public | — |
| POST | `/api/auth/logout` | Bearer | — |
| POST | `/api/auth/recover` | public | — |
| POST | `/api/auth/register` | public | — |
| GET | `/api/auth/security` | Bearer | — |
| POST | `/api/base/buildings` | Bearer | — |
| POST | `/api/base/buildings/:buildingId/collect` | Bearer | — |
| POST | `/api/base/buildings/:buildingId/demolish` | Bearer | — |
| POST | `/api/base/buildings/:buildingId/mage-study` | Bearer | — |
| POST | `/api/base/buildings/:buildingId/production` | Bearer | — |
| POST | `/api/base/buildings/:buildingId/promote-mansion` | Bearer | — |
| POST | `/api/base/buildings/:buildingId/upgrade` | Bearer | — |
| POST | `/api/base/buildings/:buildingId/workers` | Bearer | — |
| DELETE | `/api/base/buildings/:buildingId/workers/:heroId` | Bearer | — |
| POST | `/api/base/expand` | Bearer | — |
| GET | `/api/base/overview` | Bearer | — |
| GET | `/api/chat/private` | Bearer | — |
| POST | `/api/chat/private` | Bearer | — |
| GET | `/api/chat/world` | Bearer | — |
| POST | `/api/chat/world` | Bearer | — |
| GET | `/api/chronicles/heroes` | Bearer | — |
| GET | `/api/chronicles/heroes/:id` | Bearer | — |
| POST | `/api/chronicles/heroes/:id/resurrect` | Bearer | — |
| GET | `/api/combat/buffs` | Bearer | PVE_COMBAT |
| GET | `/api/combat/party` | Bearer | PVE_COMBAT |
| PUT | `/api/combat/party` | Bearer | PVE_COMBAT |
| POST | `/api/combat/session/:sessionId/advance` | Bearer | PVE_COMBAT |
| POST | `/api/combat/session/:sessionId/buff` | Bearer | PVE_COMBAT |
| POST | `/api/combat/session/:sessionId/skills/:skillCode/use` | Bearer | PVE_COMBAT |
| GET | `/api/combat/session/active` | Bearer | PVE_COMBAT |
| GET | `/api/combat/session/latest` | Bearer | PVE_COMBAT |
| POST | `/api/combat/session/start` | Bearer | PVE_COMBAT |
| POST | `/api/combat/v2/session/:sessionId/advance` | Bearer | PVE_COMBAT |
| POST | `/api/combat/v2/session/start` | Bearer | PVE_COMBAT |
| GET | `/api/combat/v2/sessions` | Bearer | PVE_COMBAT |
| POST | `/api/combat/v2/simulate` | Bearer | PVE_COMBAT |
| GET | `/api/crafting` | Bearer | — |
| POST | `/api/crafting/craft` | Bearer | — |
| POST | `/api/crafting/equipment/:instanceId/enhance` | Bearer | — |
| POST | `/api/crafting/fuse` | Bearer | — |
| POST | `/api/dungeon/floor/:floorNumber/enter` | Bearer | — |
| GET | `/api/dungeon/floors` | Bearer | — |
| POST | `/api/dungeon/instance/:instanceId/explore` | Bearer | — |
| POST | `/api/dungeon/instance/:instanceId/retreat` | Bearer | — |
| GET | `/api/dungeon/instance/active` | Bearer | — |
| GET | `/api/dungeon/templates` | Bearer | — |
| GET | `/api/dungeon/templates/:templateId` | Bearer | — |
| GET | `/api/dungeon/world-seed/reconstruct/:floorNumber` | Bearer | — |
| GET | `/api/economy/balances` | Bearer | — |
| POST | `/api/economy/exchange-scrolls` | Bearer | SUMMON |
| GET | `/api/economy/transactions` | Bearer | — |
| GET | `/api/equipment` | Bearer | EQUIPMENT |
| PUT | `/api/equipment/:itemId/equip` | Bearer | EQUIPMENT |
| POST | `/api/equipment/:itemId/pickup` | Bearer | EQUIPMENT |
| POST | `/api/equipment/:itemId/unequip` | Bearer | EQUIPMENT |
| GET | `/api/equipment/floor-drops` | Bearer | EQUIPMENT |
| PUT | `/api/equipment/heroes/:heroId/quick-equip` | Bearer | EQUIPMENT |
| POST | `/api/equipment/heroes/:heroId/quick-unequip` | Bearer | EQUIPMENT |
| GET | `/api/events` | Bearer | — |
| POST | `/api/events/missions/:missionId/claim` | Bearer | — |
| GET | `/api/gacha/banners` | Bearer | SUMMON |
| GET | `/api/gacha/banners/:bannerId` | Bearer | SUMMON |
| GET | `/api/gacha/history` | Bearer | SUMMON |
| POST | `/api/gacha/summon` | Bearer | SUMMON |
| POST | `/api/giftcodes/redeem` | Bearer | — |
| GET | `/api/hero-templates` | Bearer | HERO_COLLECTION |
| GET | `/api/heroes` | Bearer | HERO_COLLECTION |
| POST | `/api/heroes/:heroId/awaken` | Bearer | HERO_COLLECTION |
| GET | `/api/heroes/:heroId/awaken/preview` | Bearer | HERO_COLLECTION |
| POST | `/api/heroes/:heroId/breakthrough` | Bearer | HERO_COLLECTION |
| GET | `/api/heroes/:heroId/breakthrough/preview` | Bearer | HERO_COLLECTION |
| POST | `/api/heroes/:heroId/class-change` | Bearer | HERO_COLLECTION |
| GET | `/api/heroes/:heroId/imprints` | Bearer | HERO_COLLECTION |
| POST | `/api/heroes/:heroId/level-up` | Bearer | HERO_COLLECTION |
| PATCH | `/api/heroes/:heroId/lock` | Bearer | HERO_COLLECTION |
| POST | `/api/heroes/:heroId/promote` | Bearer | HERO_COLLECTION |
| POST | `/api/heroes/:heroId/promote-star` | Bearer | HERO_COLLECTION |
| GET | `/api/heroes/:heroId/promote-star/preview` | Bearer | HERO_COLLECTION |
| GET | `/api/heroes/:heroId/promote/preview` | Bearer | HERO_COLLECTION |
| PATCH | `/api/heroes/:heroId/skills/:skillCode/behavior` | Bearer | HERO_COLLECTION |
| POST | `/api/heroes/:heroId/skills/:skillCode/unlock` | Bearer | HERO_COLLECTION |
| POST | `/api/heroes/:heroId/skills/:skillCode/upgrade` | Bearer | HERO_COLLECTION |
| POST | `/api/heroes/:heroId/train` | Bearer | HERO_COLLECTION |
| POST | `/api/iap/checkout` | Bearer | — |
| GET | `/api/iap/products` | Bearer | — |
| POST | `/api/iap/receipt` | Bearer | — |
| GET | `/api/iap/transactions` | Bearer | — |
| GET | `/api/imprints` | Bearer | HERO_COLLECTION |
| GET | `/api/inventory` | Bearer | — |
| POST | `/api/inventory/items/:itemId/sell` | Bearer | — |
| POST | `/api/inventory/items/:itemId/use` | Bearer | — |
| GET | `/api/leaderboards` | Bearer | — |
| GET | `/api/leaderboards/me` | Bearer | — |
| GET | `/api/mailbox` | Bearer | — |
| POST | `/api/mailbox/:messageId/claim` | Bearer | — |
| GET | `/api/master/features` | Bearer | — |
| GET | `/api/master/skills` | Bearer | MASTER_SKILLS |
| GET | `/api/me` | Bearer | — |
| GET | `/api/medical` | Bearer | — |
| POST | `/api/medical/emergency` | Bearer | — |
| POST | `/api/medical/emergency/batch` | Bearer | — |
| GET | `/api/medical/history` | Bearer | — |
| POST | `/api/medical/resurrect` | Bearer | — |
| POST | `/api/medical/treatments` | Bearer | — |
| DELETE | `/api/medical/treatments/:heroId` | Bearer | — |
| POST | `/api/medical/treatments/batch` | Bearer | — |
| GET | `/api/parties` | Bearer | PVE_COMBAT |
| POST | `/api/parties` | Bearer | PVE_COMBAT |
| DELETE | `/api/parties/:partyId` | Bearer | PVE_COMBAT |
| PUT | `/api/parties/:partyId` | Bearer | PVE_COMBAT |
| PATCH | `/api/parties/:partyId/default` | Bearer | PVE_COMBAT |
| GET | `/api/personality` | Bearer | — |
| POST | `/api/personality/heroes/:heroId/favorite-meal` | Bearer | — |
| POST | `/api/personality/heroes/:heroId/loyalty` | Bearer | — |
| GET | `/api/profile` | Bearer | — |
| PATCH | `/api/profile` | Bearer | — |
| GET | `/api/pve/battles` | Bearer | PVE_COMBAT |
| GET | `/api/pve/battles/:battleId` | Bearer | PVE_COMBAT |
| POST | `/api/pve/battles/:battleId/action` | Bearer | PVE_COMBAT |
| POST | `/api/pve/consumables/use` | Bearer | PVE_COMBAT |
| POST | `/api/pve/dev/reset-tower` | Bearer | — |
| POST | `/api/pve/enter` | Bearer | PVE_COMBAT |
| POST | `/api/pve/parties` | Bearer | PVE_COMBAT |
| PUT | `/api/pve/parties/:partyId` | Bearer | PVE_COMBAT |
| POST | `/api/pve/parties/:partyId/deploy` | Bearer | PVE_COMBAT |
| PUT | `/api/pve/parties/:partyId/plan` | Bearer | PVE_COMBAT |
| POST | `/api/pve/squads/:squadId/auto` | Bearer | PVE_COMBAT |
| POST | `/api/pve/squads/:squadId/move` | Bearer | PVE_COMBAT |
| POST | `/api/pve/squads/:squadId/portal` | Bearer | PVE_COMBAT |
| POST | `/api/pve/squads/:squadId/recall` | Bearer | PVE_COMBAT |
| POST | `/api/pve/squads/:squadId/recall-point` | Bearer | PVE_COMBAT |
| GET | `/api/pve/state` | Bearer | PVE_COMBAT |
| GET | `/api/quests` | Bearer | — |
| POST | `/api/quests/:code/accept` | Bearer | — |
| POST | `/api/quests/:code/claim` | Bearer | — |
| GET | `/api/shop` | Bearer | — |
| GET | `/api/shop/items/:code` | Bearer | — |
| POST | `/api/shop/purchase` | Bearer | — |
| GET | `/api/support/tickets` | Bearer | — |
| POST | `/api/support/tickets` | Bearer | — |
| POST | `/api/support/tickets/:ticketId/messages` | Bearer | — |
| GET | `/api/survival` | Bearer | — |
| POST | `/api/survival/heroes/:heroId/feed` | Bearer | — |
| DELETE | `/api/survival/heroes/:heroId/rest` | Bearer | — |
| POST | `/api/survival/heroes/:heroId/rest` | Bearer | — |
| POST | `/api/survival/housing/:buildingId/assign` | Bearer | — |
| DELETE | `/api/survival/housing/heroes/:heroId` | Bearer | — |
| POST | `/api/survival/kitchen/cook` | Bearer | — |
| POST | `/api/survival/rations/quote` | Bearer | — |
| GET | `/api/survival/upkeep` | Bearer | — |
| GET | `/api/world` | Bearer | — |
| GET | `/api/world/conquest` | Bearer | — |
| GET | `/api/world/conquest/ranking` | Bearer | — |
| GET | `/api/world/conquest/seasons` | Bearer | — |
| POST | `/api/world/conquest/wonder/siege` | Bearer | — |
| POST | `/api/world/create` | Bearer | WORLD_CREATION |
| GET | `/api/world/expeditions` | Bearer | — |
| POST | `/api/world/expeditions` | Bearer | — |
| POST | `/api/world/expeditions/:expeditionId/recall` | Bearer | — |
| GET | `/api/world/global` | Bearer | — |
| GET | `/api/world/global/map` | Bearer | — |
| GET | `/api/world/global/tiles/:tileId` | Bearer | — |
| POST | `/api/world/global/tiles/:tileId/claim` | Bearer | — |
| POST | `/api/world/global/tiles/:tileId/discover` | Bearer | — |
| POST | `/api/world/global/unlock` | Bearer | — |
| GET | `/api/world/heroes/away` | Bearer | — |
| GET | `/api/world/leaderboard` | Bearer | — |
| GET | `/api/world/pvp/battles` | Bearer | — |
| GET | `/api/world/territories` | Bearer | — |
| POST | `/api/world/territories/:territoryId/abandon` | Bearer | — |
| POST | `/api/world/territories/:territoryId/upgrade` | Bearer | — |
| GET | `/api/world/territories/history` | Bearer | — |
| GET | `/api/world/tiles/:tileId/defense` | Bearer | — |
| GET | `/health` | public | — |

