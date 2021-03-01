### A Pluto.jl notebook ###
# v0.12.21

using Markdown
using InteractiveUtils

# ╔═╡ 1bbbf4d2-4c66-11eb-31f5-43392687e55a
begin
	import PlutoUI, Dates
	project_name = "FiFo" 
	date = Dates.Date(Dates.now())
	company = "Rappi"
	objective = "to explain the actual process and next steps in FIFO."
end;

# ╔═╡ 03085a30-3430-11eb-0e9c-eb819a906837
md"""
# $project_name @ $company

The 
**objective** is $objective 

See [Git repo](https://github.com/SebastianGrandaA/FIFO) and [Slides](https://docs.google.com/presentation/d/13IOPCywop9NLgNVCBP0SaJmBAkaZE7Oj1OAvI2RdE_U/edit?usp=sharing).

Last time modified: $date

"""

# ╔═╡ 90b9ddc2-4c65-11eb-15c0-616785d7aa14
md"""
$(PlutoUI.TableOfContents())
"""

# ╔═╡ c004e940-4c64-11eb-2f0b-fd0b9bd7d9da
md"""
# As-is
"""

# ╔═╡ c0464492-5490-11eb-0d57-a79f48541034
md"""
## [The big picture](https://drive.google.com/file/d/1YofBX-tL13gAAACh5GiK14XzTBuqq1Jt/view?usp=sharing)

$(PlutoUI.LocalResource("Resources/FIFO-V1.png"))

[Click](https://drive.google.com/file/d/1YofBX-tL13gAAACh5GiK14XzTBuqq1Jt/view?usp=sharing) to access editable file.
"""

# ╔═╡ 939ff002-5439-11eb-22b9-a9df5dbd87e6
md"""
## Al-switch

"""

# ╔═╡ b62c9750-4cfb-11eb-1a50-5bf8b0327593
md"""
### Idea

Due to the uncertainty of delivery process at Rappi, last-minute events are frequent and many decisions have to be made in real time. 

Imagine an order gets ready 15 minutes before its assigned courier arrives to the store, and there are other couriers waiting for their orders. Makes sense that one of those couriers could take that finished order instead of waiting.

That's exactly FIFO (First-in, First-out): a technique that assigns first-in couriers with first-out bundles. See the [slides](https://docs.google.com/presentation/d/13IOPCywop9NLgNVCBP0SaJmBAkaZE7Oj1OAvI2RdE_U/edit?usp=sharing) for an example. 

Given:
- Set of $S$ active stores with FIFO enabled, 
- Set of $B$ eligible bundles at a given store,
- Set of $C$ couriers assigned to $B$ at a given store.

Define:
- Binary decision variable $X_{ij}$ equals to $1$ if bundle $i$ assigned to courier $j$; $0$ otherwise,
- Assignment $A_{ij}$ that indicates the $A: i \mapsto j$ relationship for each pair of bundle-courier,
- Set of $P$ prospects or feasible assignments $ A: i \mapsto j$ subject to our constraints,
- Time $ARR_{i}$ in seconds since courier's arrival date calculated with `max(0, now - arrival)`,
- Time $CT_{i}$ in seconds since bundle's oldest order got ready calculated with `max(0, now - ready)`,

Then, we seek to find a set of updated assignments that **minimizes total waiting time at store.**

Formally, we assign couriers and orders that have been waiting the longest:

$MAXIMIZE \sum_{i \in B} \sum_{j \in C} X_{ij} \times ( CT_{i} \times ARR_{j} )$

Subject to all bundles and couriers must be **matched exactly once**:

$\forall i \in B: \sum_{j \in C} X_{ij} = 1$

$\forall i \in C: \sum_{j \in B} X_{ij} = 1$


"""

# ╔═╡ f07d2170-4dd4-11eb-1397-0196159d51f7
md"""
### Code walkthrough

Let's get deeper into the algorithm. Note that some logic might not be exactly as written in the project repository, but the functionality should work the same.

Follow the architecture diagram.

"""

# ╔═╡ 728d5bf0-4ddd-11eb-2f9d-d70564d00c9c
md"""

A glance at the most relevant structures of the algorithm:

"""

# ╔═╡ 203b7970-4dda-11eb-2c4b-bd94e7c86a7d
md"""

```julia
mutable struct Store
	ID::String
	fifo_enabled::Bool
	active::Bool
end
```

```julia
mutable struct Courier
	ID::String
	active::Bool
	on_route::Bool
	at_store_since::Dates.Date
	details::Any{debt, kit_size, skills} # set of characteristics
end
```

```julia
mutable struct Order
	ID::String
	courier_assigned::Courier
	is_ready_since::Dates.Date
	details::Any{cashless, skills}
end
```

```julia
mutable struct Bundle
	ID::String
	store::Store
	orders::Array{Order, 1}
	courier::Courier
	to_reassign::Bool # true if able to reassign.
end
```

```julia
mutable struct Pipeline
	store::Store
	bundles::Array{Bundle, 1}
	couriers::Array{Courier, 1}
	parameters::Any{debt, elevation_threshold, max_distance}
	invalid::Bool # false if able to reassign
end
```


```julia
mutable struct Assignment
	store::Store
	assingment::Dict(Bundle => Courier)
end
```

"""

# ╔═╡ 9d2f9f88-543a-11eb-0a37-a1e9f5c59a31
md"""
The main functionality of `al-switch` is the **FIFO** algorithm:
"""

# ╔═╡ 16d76a30-4dce-11eb-141d-63cbfd7dfa87
md"""
**FIFO**

- This is a scheduled task running each 20 seconds in every enabled city.

- Reassign bundles to couriers by sending a request to `/dispatch/order-dispatcher`

- Flow: `/al-switch/server/__init__.py` => `application.py` => `process.py` => `processor.py`

```julia
function FIFO(seconds_to_timeout = 20)

	for city in enabled_cities()

		for store in eligible_stores(city, boo_grouped = false)
			
			orders = eligible_orders(store)
			couriers = assigned_couriers(orders)
			params = dispatch_parameters(city)
			pipeline = build_pipeline(orders, couriers, params) 
					# set of bundles and couriers ::Pipeline with a sequence of
						# post-processors applied (details in section below)

			Dispatch.order_dispatcher!(pipeline) # request to '/dispatch'

		end

		timeout(seconds_to_timeout)
	end
end
```

"""

# ╔═╡ 17794db0-4e09-11eb-086b-2d4788c5ebd2
md"""
`/al-switch` makes a request to `/dispatch` to re-optimize the assignments.
"""

# ╔═╡ 25c064d0-4e09-11eb-2791-b370a83dd02a
md"""
**order_dispatcher!**

- This algorithm formulates the assignment problem and solves it.

- Then calls back to `/al-switch` to decide what to do with the results.

- Request to: `/al-switch/reassign`

- Flow: `/dispatch/dispatch.py/dispatch_orders()`


```julia
function order_dispatcher!(pipeline::Pipeline)
	if validate(pipeline.bundles, pipeline.couriers) # no missing entities
		optimized_assignment = dispatch(pipeline.bundles, pipeline.couriers)

		AlSwitch.reassign!(optimized_assignment) # call back to al-switch
	end
end
```

"""

# ╔═╡ 0e4edf80-4e12-11eb-0df4-a1c425448288
md"""

The outputs of `Dispatch` are assignments that might be:
- **Re-assignments** if $A_{i} \neq A_{i+1}$,
- **Final assignments**: when both $ b $ and $ c $ are ready-to-go.

... or both. Either way, it hits back to `/al-switch` and perform the actions.
"""

# ╔═╡ e034a850-4e11-11eb-19e1-bb60d797c6d7
md"""
**reassign!**

- This is the most important process in al-switch.

- Executes a sequence of **independent steps**. Each one filters a subset of data and performs an operation.

Steps:

- `Replace`: sends a `replace_dispatch` events to `/order-modification` to make re-assignments and final assignments effective.

- `Mark`: marks final assignments in `Redis Reassign Repository` and updates couriers in `Redis Couriers Repository`.

- `Regenerate`: rebuilds bundles (`/bundler`) and updates earnings (`/rt-earnings`) of both re-assignments and final assignments.

- `Event`: **clears the cache** at `/storekeeper-orders-ms` for final assignments. This is important to avoid inconsistencies.

- `Notify`: sends push notification to final assignments and silent notifications to the re-assignments through `/communications-ms`.

```julia
function reassign!(original_assignments::Array{Assignment, 1}, reassignments::Array{Assignment, 1})

	steps = ["Replace", "Mark", "Regenerate", "Event", "Notify"]

	pipeline = build_pipeline(original_assignments, reassignments) 

	for step in steps
		step_filter!(step, pipeline)
		perform_action!(step, pipeline)
	end


end
```

"""

# ╔═╡ d9be8480-4df5-11eb-3ec2-8d5643aa8521
md"""
So far, some functions have been black-box. Here is what's inside:
"""

# ╔═╡ d4e57140-4e0d-11eb-1125-33ee5791dee0
md"""
**dispatch**

- Generates the prospects and solves a balanced assignment problem.

- Reference: `/dispatch/dispatcher/order_dispatcher.py`

```julia
function dispatch(bundles::Array{Bundle, 1}, couriers::Array{Courier, 1})
	prospects = generate_prospects(bundles, couriers) # arcs of the graph
	time_estimation = estimate_time(prospects)
	matches = match!(prospects, time_estimation) # optimize

	return matches
end
```

"""

# ╔═╡ 9cde62e0-4ded-11eb-2e8e-bfe3951bfb9d
md"""
**eligible_stores**

- Retrieve all stores that are active and have FIFO enabled from `Redis` or `/al-settings`.

- Reference: `/al-switch/services/stores.py/`

```julia
function eligible_stores(city; boo_grouped = false)::Array{Store, 1}
	cache_stores = RedisRepository.get(city, boo_grouped, active_enabled = true)
	
	if !(cache_stores isa missing)
		return cache_stores
	else
		stores = SettingsAPI.get(city, boo_grouped, active_enabled = true)  
		RedisRepository.set(city, stores) # set retrieved stores to cache
		return stores
	end

end
```

"""

# ╔═╡ ed2e4190-4df5-11eb-378d-23c7c47911c7
md"""
**eligible_orders**

- Retrieve all active orders for a given store from `/al-orders`.

- Reference: `al-switch/services/api/orders.py/OrdersAPI`


```julia
function eligible_orders(store::Store)::Array{Order, 1}
	return OrdersAPI.get(store, active = true)
end

```
"""

# ╔═╡ e56aa570-4df5-11eb-0547-4986ecd9d3d8
md"""
**assigned_couriers**

- Retrieve all the assigned couriers to a given set of orders from `/al-couriers`.

- Reference: `al-switch/services/api/couriers.py/CouriersAPI`


```julia
function assigned_couriers(orders::Array{Orders, 1})::Array{Courier, 1}
	couriers = [order.courier_assigned for order in orders]
	return CouriersAPI.get_details(couriers)
end

```
"""

# ╔═╡ 77301f50-4df9-11eb-3361-4d11e726c554
md"""
**dispatch_parameters**

- Retrieve the dispatching parameters from `Redis Repository` or `/al-settings`.

- Reference: `al-switch/services/algorithm.py/AlgorithmService`

```julia
function dispatch_parameters(city)::Dict{String, Int64}
	cache_params = RedisRepository.get(city)

	if !(cache_params isa missing)
		return cache_params
	else
		params = SettingsAPI.get()  
		RedisRepository.set(city, params) # set retrieved params to cache
		return params
	end

end
```

"""

# ╔═╡ 72b48fd0-4dd9-11eb-2d46-b54772d32d69
md"""
**build_pipeline**

- For a given store, prepares the input data to the reassign algorithm.

- Applied a **sequence of post-processors** in order to send the problem instance to the optimization algorithm placed in `Dispatch`.

- Reference: `al-switch/services/data/__init__.py/DataManagerService`

Post-processors:

- `ManualReplacement`: filters orders with manual assignments and save them as final.

- `Reassigned`: filters reassigned orders and couriers.

- `NoShopper`: filters orders with no shopper assigned.

- `OrdersFallback`: filters orders with fallback turned off.

- `GroupBundles`: groups the orders into bundles.

- `BundleDisparity`: filters unpaired bundles.

- `Mismatch`: filters in case of bundle mismatching.


```julia
function build_pipeline(orders::Array{Order, 1}, couriers::Array{Courier, 1}, params::Dict{String, Int64})::Pipeline

	post_processors = ["ManualReplacement", "Reassigned", "NoShopper", "OrdersFallback", "GroupBundles", "BundleDisparity", "Mismatch"]
	pipeline = create(couriers, params)

	for process in post_processors
		process(pipeline, processor) # apply each function to the pipeline.
	end

	return pipeline
end
```

"""

# ╔═╡ f88607ce-5455-11eb-3983-338d9c0dd35c
md"""
### Key takeaways

1. FIFO is a reward for couriers that arrive first at the store: it reassigns the **first-in couriers with the first-out bundles**.

2. Graph arcs are constructed with the **prospects**. An arc does not exists if $ A: b \mapsto c $ is unfeasible. 

3. Each bundle has **at least the initial connection**. Therefore, in worst case scenario, a courier gets reassigned to it's same bundle.

4. The arc weights are positive numbers only if the **courier is at store** AND at **least one order in the bundle gets ready**.

5. An assignment $ A: b \mapsto c $ is **final** when the **whole bundle** and the **assigned courier are ready-to-go**.

6. The scope of the re-assignment is **bundles to couriers** and **couriers of the same store**. 

7. If courier isn't at store yet, the bundle assigned might be taken by an in-store courier or keep getting assigned to the same courier.

8. If courier is at store, it might get re-assgined multiple times until a bundle gets ready.

9. If a bundle has **multiple stores**, FIFO will only work in the first store since we cannot deteriorate the bundles.

10. The post-processors set up the problem instance, then the optimization algorithm determines the best assignments, and finally the steps in ReassignManager make the changes effective.

11. Despite it is not a complex optimization problem to solve, we are making optimization requests every 20 seconds even though no optimization is needed. We then might think about a more efficient way to reassign.

12. Proposals should focus on **event-driven architecture and multiple-dispatch movements**.


"""

# ╔═╡ ef530810-4dce-11eb-2e2e-0f0531c6a3e4
md"""
## Al-switch-api
"""

# ╔═╡ e8cca6e2-4dce-11eb-2205-c54214163885
md"""

Bundle information is hidden to the courier until a final reassignment is made. 

In that moment, the app needs to get updated and `/storekeeper-orders-ms` retrieves the data from cache. If not found, makes a request to `/al-switch-api`.

Therefore, `/al-switch-api` **provides the status of bundles, orders and couriers**, such as courier reassignments, courier position in store's queue or bundle total earning.

"""

# ╔═╡ b9aeba46-54af-11eb-3c80-8393d34d4893
md"""
### Available requests
"""

# ╔═╡ 16568680-4e33-11eb-301c-0518e0edfe20
md"""
**POST `/couriers/active`**

Retrieves:
- Bundle information and earnings.
- Order reassignments.
- Queue position


Example body:

```
{ 
"courier_id": 123, 
"orders": [455621725, 555821525] 
}
```

Expected output:

```
{
  "bundles": [
    {
      "courier_id": 123,
      "bundle_id": "aaaaa-aaa",
      "total_earnings": 2500,
      "queue_position": "A1",
      "orders": [
        {
          "id": 455621725,
          "reassigned": true,
          "to_reassign": true
        },
        {
          "id": 555821525,
          "reassigned": true,
          "to_reassign": true
        }
      ]
    }
  ]
}
```
"""

# ╔═╡ 755a7ada-547b-11eb-16a2-01bc36d14af1
md"""
**POST `/orders/status`**

Retrieves:
- Bundle information (`al-bundler`).
- Basic courier information.
- Quantity of in-store and on-route couriers


Example body:

```
{
    "store_id": 78901,
    "orders": [455621725]
}
```

Expected output:

```
{
    "orders:": [
        {
            "order_id": 455621725,
            "bundle_id": "aaaaa-aaa",
            "courier": {
                "id": 123,
                "name": "ABC"
            }
        }
    ],
    "couriers": {
        "in_store": 2,
        "to_store": 5 
    }
}
```
"""

# ╔═╡ a85d0abc-547e-11eb-3a20-b3c129dfc234
md"""
**POST `/orders/active`**

Retrieves:
- Bundle information (`al-bundler`).
- RT assignation status (`storekeeper-ms`)
- Estimated cooking time (`/store-time-stimator`)


Example body:

```
{
"partner_id": 12345,
"store_id": 78901,
"orders": [{
		"id": 455621725,
		"products": []}]
}
```

Expected output:

```
{
  "orders:": [
    {
        "order_id": 455621725,
        "cooking_time": {
            "min_cooking_time": 5,
            "max_cooking_time": 40,
            "default_cooking_time": 15
        },
        "courier": {...
        }
    },
}
```
"""

# ╔═╡ 06a5b88c-5487-11eb-0c30-831f191d8ba6
md"""
# Simulation
"""

# ╔═╡ 10d64660-5490-11eb-2657-13aebc98b856
md"""

As mentioned, FIFO makes decisions based on the arrival of two main events:

1. Courier arrives at store before it's assigned order is ready,
2. Order is ready before it's assigned courier arrives at store.

Let a final re-assignment $ R: b \mapsto c $ be formed when both $ b $ and $ c $ are ready-to-go.

We seek to measure the **impact of policies, algorithm and architecture modifications** in the overall operation performance.


### Events characterization

Define:

- $ B(t) \sim PP(\lambda_{b}) $: counts independent bundle arrival events.
- $ C(t) \sim PP(\lambda_{c}) $: counts independent courier arrival events. 

Operational and benchmark metrics must be evaluated to compare different scenarios:

**Resource utilization (RU)**
- **Measures:** quantity of optimization requests against quantity of effective swaps.
- **Granularity:** for each city in a given day.
- **Question:** our optimization efforts are justified by the quantity of effective swaps?
- **Opportunity:** event-driven architecture.
- **Success:** minimize RU.

$RU = \frac{requests}{swaps}$


**Waiting time distribution (WT)**
- **Measures:** total time the orders and bundles wait at the store.
- **Granularity:** for each assignment in a group of stores.
- **Question:** is it worth to group the stores in the reassignment process?
- **Opportunity**: store-type specific reassignment parameters, such as task scheduling time.
- **Success**: find interesting aggregation policies and minimize expected waiting time $ EWT $.

$WT_{A} = max(0, now - arrival) + max(0, now - ready)$


**Bundle inefficiency (BI)**
- **Measures:** courier's insatisfaction by dividing the total bundle time  + total waiting time and the quantity of orders in the bundle.
- **Granularity:** for each group of stores.
- **Question:** is it worth to modify courier bundles in the reassignment process (batching for instance).
- **Opportunity**: inter- and intra-bundle movements.
- **Success**: minimize $ BI $.


$BI_{b} = \frac{T_{b} + WT}{Q_{b}} ; \forall{b \in B}$

**Reassignment event traffic (RET)**
- **Measures:** how frequent are reassignment events compared to the total event arivals. In other words, divides the difference of arrival rates between two different-type events with the total quantity of bundles (or couriers) assigned.
- **Granularity:** for each group of stores.
- **Question:** how many requests should we expect in an event-driven architecture?
- **Opportunity**: event-driven architecture with a traffic stop light.
- **Success**: a way to coordinate events in an adaptive pipeline.

$RET_{g} = \frac{| \lambda_{b} - \lambda_{c} |}{bundles}$


**Total adjusted time savings (TATS)**
- **Measures:** how much time we save compared to the traffic of the operation by substracting the total time of the solutions with and without reassignments and devide it by the quantity of bundle events.
- **Granularity:** for each group of stores.
- **Question:** which characteristics have the group of stores with the highest priorization?
- **Opportunity**: prioritize the tests in a given set of locations.
- **Success**: group locations by opportunity priorization to minimize TATS.

$TATS = \frac{time(A_{i+1}) - time(A_{i})}{bundles}$

**Total computing time (TCT)**
- **Measures:** total computing time of all the available optimization algorithms times the binary decision $ X_{\alpha} $ to compute the algorithm $ \alpha $.
- **Granularity:** for each assignment $ A $.
- **Question:** how much computing time would be save if introducing new - and simpler - optimization movements?
- **Opportunity**: multiple dispatch movements guided by a local search algorithm.
- **Success**: minimize TCT.

$TCT_{A} = time(\alpha) \times X_{\alpha}$


Therefore, to estimate those metrics we should simulate different scenarios with different combination of **variables**:

| Simulation variable         	| Type       	| Description                               	|
|-----------------------------	|------------	|-------------------------------------------	|
| Reactive trigger            	| Decision   	| Event-based architecture                  	|
| Task scheduling time        	| Continuous 	| Frequency of process execution            	|
| Multiple dispatch movements 	| Decision   	| Operators: batching, intra- inter- bundle 	|
| Store groupings             	| Decision   	| Aggregation policies                      	|
| Traffic light threshold     	| Discrete   	| Max traffic allowed for a time interval   	|


Finally, our main simulation hypothesis is that by introducing an **event-driven architecture with multiple dispatch operators**, we would minimize TCT, TATS, BI, EWT and RU.

"""

# ╔═╡ Cell order:
# ╟─1bbbf4d2-4c66-11eb-31f5-43392687e55a
# ╟─03085a30-3430-11eb-0e9c-eb819a906837
# ╟─90b9ddc2-4c65-11eb-15c0-616785d7aa14
# ╟─c004e940-4c64-11eb-2f0b-fd0b9bd7d9da
# ╟─c0464492-5490-11eb-0d57-a79f48541034
# ╟─939ff002-5439-11eb-22b9-a9df5dbd87e6
# ╟─b62c9750-4cfb-11eb-1a50-5bf8b0327593
# ╟─f07d2170-4dd4-11eb-1397-0196159d51f7
# ╟─728d5bf0-4ddd-11eb-2f9d-d70564d00c9c
# ╟─203b7970-4dda-11eb-2c4b-bd94e7c86a7d
# ╟─9d2f9f88-543a-11eb-0a37-a1e9f5c59a31
# ╟─16d76a30-4dce-11eb-141d-63cbfd7dfa87
# ╟─17794db0-4e09-11eb-086b-2d4788c5ebd2
# ╟─25c064d0-4e09-11eb-2791-b370a83dd02a
# ╟─0e4edf80-4e12-11eb-0df4-a1c425448288
# ╟─e034a850-4e11-11eb-19e1-bb60d797c6d7
# ╟─d9be8480-4df5-11eb-3ec2-8d5643aa8521
# ╟─d4e57140-4e0d-11eb-1125-33ee5791dee0
# ╟─9cde62e0-4ded-11eb-2e8e-bfe3951bfb9d
# ╟─ed2e4190-4df5-11eb-378d-23c7c47911c7
# ╟─e56aa570-4df5-11eb-0547-4986ecd9d3d8
# ╟─77301f50-4df9-11eb-3361-4d11e726c554
# ╟─72b48fd0-4dd9-11eb-2d46-b54772d32d69
# ╟─f88607ce-5455-11eb-3983-338d9c0dd35c
# ╟─ef530810-4dce-11eb-2e2e-0f0531c6a3e4
# ╟─e8cca6e2-4dce-11eb-2205-c54214163885
# ╟─b9aeba46-54af-11eb-3c80-8393d34d4893
# ╟─16568680-4e33-11eb-301c-0518e0edfe20
# ╟─755a7ada-547b-11eb-16a2-01bc36d14af1
# ╟─a85d0abc-547e-11eb-3a20-b3c129dfc234
# ╟─06a5b88c-5487-11eb-0c30-831f191d8ba6
# ╟─10d64660-5490-11eb-2657-13aebc98b856
