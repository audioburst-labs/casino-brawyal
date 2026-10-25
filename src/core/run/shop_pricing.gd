class_name ShopPricing
extends RefCounted
## What a shop actually charges (patch 0.125). The stock stores the BASE price it
## rolled; the VIP Comp Card takes 10% off whatever is on the shelf, and because
## the shop asks again on every refresh, buying the card discounts the rest of
## the shelf straight away.

const VIP_DISCOUNT := 0.1


## `base` rounded half-up after the discount, never below 1.
static func price(run: RunState, base: int) -> int:
	if run != null and run.relic_ids.has(&"vip_comp_card"):
		return maxi(1, int(floor(base * (1.0 - VIP_DISCOUNT) + 0.5)))
	return base
